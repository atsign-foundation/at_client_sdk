# implementation-plan.md — the detail

The plan as it stood on 2026-08-16 below the header: every project entry, the
dependency graph, the phase sections, the backlog and the D1 burn-down.
**The live plan is [`../implementation-plan.md`](../implementation-plan.md)**,
which carries full detail for open work only and one row each for parked and
completed items, every row pointing back here.

**Two edits since the snapshot, and the second is prose.** Moving this file down
a directory broke every relative link in it, so `](design.md)`,
`](acceptance.md)` and `](roadmap.md)` were repointed to `../` — 224 lines. Then
on 2026-08-16 **item 18 of section 14.19 was struck and closed** when the
release it complained about was deleted outright; item 18 lives here, not in the
live plan, so the closure had to land here.

⚠️ **This file is therefore no longer link-identical to the snapshot, and it is
4,087 lines rather than the reference's 4,039.** Re-derive rather than trusting
that sentence — the changed lines outside the link repointing are item 18's and
this header's, and nothing else:

```bash
diff <(git show a5bf04d75:docs/projects/pq/implementation-plan.md) \
     docs/projects/pq/detail/implementation-plan.md
```

⚠️⚠️ **Every STATUS line below is as of 2026-08-16 morning and is not current.**
The burn-down's row 12, for one, still calls 14.24 open with an unmerged
at_server PR; both are false. The live plan owns status. This file is here for
the detail a live row points at, not for what is done.

⛔ **Links to `decisions.md` were deliberately NOT repointed, and must not be.**
The anchored ones (`](decisions.md#105-…)`) resolve *inside this directory*, to
the ruling bodies in [`decisions.md`](decisions.md) — which is where a citation
wants to land. The live ledger one level up is **bodyless by design** and
carries zero `## <number>.` headings, so "fixing" these to
`](../decisions.md#…)` would break every one of them at once while looking like
a consistency sweep. Re-derive before believing this:

```bash
grep -oP '\]\(decisions\.md#' detail/implementation-plan.md | wc -l  # 158 links
grep -cP '\]\(decisions\.md#' detail/implementation-plan.md          # on 142 lines
grep -cE '^## [0-9]+b?\. ' ../decisions.md   # 0 — the index has no ruling anchors
grep -cE '^## [0-9]+b?\. ' decisions.md      # 107 — the bodies are here
```

⚠️ This block said **141** until 2026-08-16. It is 158 links on 142 lines; the
two are different questions and `grep -c` answers the second even with `-o`, so
a count taken that way reads low and looks authoritative.

The 25 *bare* `](decisions.md)` links are the arguable ones: they land on the
body dump rather than on the index a general "see the ledger" reference wants.

Item ids are permanent. `14.13`, `14.19 item 11` and their siblings are cited
from production dartdoc and from `blockers.dart`, so an item keeps its id when
it moves between TODO, PARKED and DONE.

⚠️ **Read the live plan first.** This file still describes completed work in
the present tense, because it is a snapshot rather than a maintained document —
that is exactly why it is not the one you work from.

---

# Implementation Plan — Unified project sequence & dependency graph for D1 (PQ-safe nskey data path)

**Status:** working execution plan (prescriptive). The single, plan-level backlog for all of **D1**
— making Atsign Protocol messaging post-quantum-safe via the single-tier `nskey` data path.
**Scope:** all of **D1** per [decisions.md](decisions.md) — single-tier `nskey`. `at/pqmls` cross-atSign
groups are **D2**, referenced here only as the carve (D2-1), never detailed. Covers the D1 packages
**D1-S / D1-A / D1-B / D1-C / D1-D / D1-F** (D1-E is D2 prep).
**Format:** dependency graph + numbered projects. Each project is ~1–3 PRs and lists Goal / Builds-on /
Deliverables-pointer / Acceptance-pointer / Effort / Watch-outs / `coversD1`, and **depends only on
strictly-earlier projects** (no forward dependencies).
**Lane:** this doc carries **sequencing, the dependency graph, waves/parallelism, effort, publish
gates, the critical path, the coverage map, and the open-decisions pointer — only**. For *how* each
project works see [design.md](../design.md); for the given/when/then acceptance tests see
[acceptance.md](../acceptance.md); for the *why*/decision rulings see [decisions.md](decisions.md); for
the high-level trajectory see [roadmap.md](../roadmap.md). No design detail, no key shapes, no
given/when/then here.

## Table of contents

- [0. Purpose, scope & how to read this plan](#0-purpose-scope--how-to-read-this-plan)
- [1. Wave 0 — already landed baseline (do not re-plan)](#1-wave-0--already-landed-baseline-do-not-re-plan)
- [2. Dependency graph (ASCII) — critical path to D1 GA + parallel tracks](#2-dependency-graph-ascii--critical-path-to-d1-ga--parallel-tracks)
- [3. Phase A — PQ primitives & enrollment key (P-1, P-2, P-3)](#3-phase-a--pq-primitives--enrollment-key-p-1-p-2-p-3)
- [4. Phase S — Structural enablers / key management (S-1, S-2, S-3, S-5, S-6, KF-1)](#4-phase-s--structural-enablers--key-management-s-1-s-2-s-3-s-5-s-6-kf-1)
- [5. Phase SS — Secret-sharing substrate (SS-1a, SS-1b, SS-1c, SS-2, SS-3, SS-4)](#5-phase-ss--secret-sharing-substrate-ss-1a-ss-1b-ss-1c-ss-2-ss-3-ss-4)
- [6. Phase B — the nskey data path (B-1, the D1 centrepiece)](#6-phase-b--the-nskey-data-path-b-1-the-d1-centrepiece)
- [7. Phase RF — existing-client retrofit (RF-1, RF-SRV, RF-2b, RF-2c)](#7-phase-rf--existing-client-retrofit-rf-1-rf-srv-rf-2b-rf-2c)
- [8. Phase R/B — rollout, rotation, retirement & versioning (R-1, SH-1, B-2, KE-1, B-3, ON-1, R-2)](#8-phase-rb--rollout-rotation-retirement--versioning-r-1-sh-1-b-2-ke-1-b-3-on-1-r-2)
- [9. Phase D2 — referenced only (D2-1, out of D1 GA)](#9-phase-d2--referenced-only-d2-1-out-of-d1-ga)
- [10. Cross-cutting: publish gates, critical path, waves/parallelism, testing](#10-cross-cutting-publish-gates-critical-path-wavesparallelism-testing)
- [11. Coverage map (D1 package / UC → project)](#11-coverage-map-d1-package--uc--project)
- [12. Open decisions pointer & verification provenance](#12-open-decisions-pointer--verification-provenance)
- [13. Phase IS — inter-server PQ authentication (IS-1)](#13-phase-is--inter-server-pq-authentication-is-1)
- [14. Backlog — carried items with no owning project](#14-backlog--carried-items-with-no-owning-project)
- [15. D1 burn-down — the single index of what D1 owes](#15-d1-burn-down--the-single-index-of-what-d1-owes) — *start here for "what is left"; every row carries the command that re-derives it*

---

## 0. Purpose, scope & how to read this plan

This is the unified, plan-level backlog for D1. The project ids used throughout — `P-1/P-2/P-3`,
`S-1`/`S-2`/`S-3`/`S-5`/`S-6`, `SS-1a/b/c`/`SS-2`/`SS-3`/`SS-4`, `B-1`, `RF-1`/`RF-SRV`/`RF-2b`/`RF-2c`,
`R-1`/`R-2`, `SH-1`, `B-2`/`B-3`, `KE-1`, `KF-1`, `ON-1`, `IS-1`, `D2-1` — name the work as it lands in
dependency order. Each project
entry is plan-altitude: a one-line Goal, what it **builds on**, a pointer to its deliverables in
[design.md](../design.md), a pointer to its acceptance tests in [acceptance.md](../acceptance.md), an effort
size, watch-outs, and a `coversD1` line tying it back to the D1 workstreams.

**Operating principles:**

- **Partition by package.** Four package-domain tracks keep concurrent PRs off each other's files:
  - **Track A — crypto primitives + providers:** `at_chops` (stateless core + HPKE) → the nskey data
    path providers (`at/nskey` + `at/symmetric/AES/GCM`), `secret_sharing/`, `crypto/group/`.
  - **Track B — key management:** `at_auth` (extend `AtKeys` in place, `AtKeysIo` runtime persistence, the
    WASM barrel split) → the PQ enrollment-conveyance key.
  - **Track C — at_client crypto seam + migration:** `crypto.dart` / `crypto_runtime.dart` / `legacy/`,
    `AtClientPreference`; the publish ladder.
  - **Track D — storage + platform + consumers:** `LocalKeystoreAtKeysIo`, the updatable `.atKeys`
    file path, `at_onboarding_cli` / `at_client_flutter` / `at_cli_commons`.
  Within `at_client/crypto/`, the file partition keeps A and C apart: **C** owns `crypto.dart`,
  `crypto_runtime.dart`, `legacy/`; **A** owns `crypto/group/`, `crypto/nskey/` (new), `secret_sharing/`.
  The nskey providers are mostly new files — low collision by construction.
- **Land contracts first.** Merge the tiny interface PRs (the `pqSeal` signature, the extended
  `AtKeys`/`AtKeysIo` API, the `CryptoContext.keys` field) first, stubs OK, so every track compiles against
  stable shapes and never blocks on another.
- **Keep merges additive / flag-gated** so trunk stays releasable at every commit boundary.
- **Every project needs a named owner.** Each project id (`P-1`, `SS-1a`, `B-1`, …) is assigned a single
  accountable owner before its first PR; owner names are **TBD** until assigned. The owner shepherds the
  project's PRs, publish/floor steps, and conformance to the current [decisions.md](decisions.md) rulings.

**Enrollment model.** This plan uses the **1:1:1 / fresh-enrollment-retrofit** model: a single APKAM
keypair per enrollment, and an `EnrollParams.metadata`-borne key package on `enroll:request` (no separate
`enroll:metadata` verb). The rationale is in [decisions.md](decisions.md).

---

## 1. Wave 0 — already landed baseline (do not re-plan)

These are **merged to trunk** (verified) and gate everything downstream. Stated once:

- **#1930 — the M0 pluggable-crypto seam** (`at_client`, merged 2026-06-22): stateless
  `CryptoProvider{id, encrypt, decrypt}`; `CryptoRuntime` routing put/get/notify/sync by
  `appMetadata.providerId`; built-in `LegacyCryptoProvider` fallback; `shouldEncrypt=false` no-crypto
  path; the Mode-B cached-client reconcile fix (a same-atSign re-set adopts the new `preference.crypto`).
  `CryptoContext` is `{atClient}`; there is no `CryptoRegistry`, `CryptoPolicy`, or `CryptoStorage`. **This
  is the migration machinery the whole rollout rides.**
- **#1993 — `pqSeal`/`pqOpen` HPKE primitive** (`at_chops`, merged 2026-06-22): X-Wing KEM + HKDF-SHA256
  + AES-256-GCM, stateless, on `at_chops` **3.3.0**, **published to pub.dev 2026-06-23**. The stateless
  functional surface + `@Deprecated AtChopsImpl` shim are largely present too.
- **PR #2035 (design fixes)** — merged.
- Baseline pins: `at_commons` **5.11.0** (`appMetadata` wire field); `at_chops` **3.3.0 (published)** (X-Wing /
  AES-256-GCM / HKDF / HMAC); `at_persistence` **5.x** commit-log-free keystore; **Phase-6
  at_chops-sole-crypto routing** in at_lookup / at_auth / at_onboarding_cli (#1995–1998, merged).

**Design:** single-tier `nskey`; group/`at/pqmls` is D2 — see [decisions.md](decisions.md).

The file-partition/track detail and the `CryptoConfig`/`CryptoRuntime` mechanics live in
[design.md](../design.md).

---

## 2. Dependency graph (ASCII) — critical path to D1 GA + parallel tracks

```
                 ┌──────────────────────── PQ primitives ───────────────────────┐
  [#1993 done]→  P-1 at_chops 3.3.0 (published)    P-2 mldsa65 verify (SATISFIED on trunk; publish 3.4.x)
                     │                                   │
  [#1930 done]→  S-2 CryptoContext.keys (additive)       │
                 S-1 at_auth AtKeys/AtKeysIo extend-in-place ─→ S-3 LocalKeystore/.atKeys updatable
                                                  │
   Substrate (SS-*)                                │
   SS-0 land WP-SS substrate baseline (PR #2037, reworked to 1:1:1 / flat listns / no-write-path) ─┐
   SS-1a commons grammar(publish) → SS-1b server verbs+live → SS-1c client wired ◀─────────────────┘
                                          │
                                    SS-2 wired-into-AtClient + wake-up
                                          │
                                    SS-3 hardening + single-key + signingAlgo verify ◀── P-2
                                          │
                P-3 pqpublickey key ──→ SS-4 nskey mint + pqpublickey lifecycle
                                          │
   ═══ CRITICAL PATH TO D1 GA (re-derived 2026-08-05, decisions 36-41) ═══
                            B-1 the nskey DATA PATH (providers + cold-start)
                                          │
                            R-1 → shrunk to disallowLegacyEncryption (DELIVERED);
                                  markers/negotiation built then REMOVED (decisions 36)
                                          │
                            SH-1 key-material self-heal (nskey pull + approve-push + chain sweep)
                                          │
              RF-SRV server self-enroll ──┤   ◀── every scenario's "upgrade the enrollment" (decisions 40)
                                          │
                            B-2 nskey rotation + revocation (B5/B6)  ◀── RF-1 + SS-3 (fan-out only)
                                          │
                            KE-1 selectable KEM + negotiated construction  ◀── at_chops 3.6.0 (UNPUBLISHED)
                                  (moves the wire 0x01→0x02; ML-KEM-1024 at 0x03)
                                          ▼
                         ▶ at_client 3.14.x = D1 GA (rebuild = reader; the app's 4.x release = PQ writer)

   Off the GA critical path (parallel):
     RF-2b PQ-APKAM mint + self-retrofit → RF-2c upgrade + e2e   (RF-1 confirm)
     B-3 selfEncryptionKey retirement (RE-TIMED by decisions 37: client-side stop is ecosystem-gated)
     ON-1 PQ-native onboarding (publickey published by DEFAULT per decisions 37)
     S-5 at_auth 4.0 WASM split → S-6 consumer bumps          D2-1 at/pqmls carve + D1-E (D2)
     KF-1 .atKeys-at-rest protection + backup/restore (builds on S-3)
     IS-1 inter-server PQ auth (FROM/POL: swap challenge signature RSA→ML-DSA-65, PR #2683) — no KEM, no cert; builds on published at_chops 3.4.x (ungated)
     R-2 at_client 4.0 (apply the pqActive posture defaults - every axis, decisions 70) - final; NO CLIENT-SIDE WORK OUTSTANDING as of 2026-08-17, gated on the ecosystem floor alone (see 14.33)
```

**Hosted-publish ordering (stated once).** `at_chops` (`P-1`, `P-2`) and `at_commons` (`SS-1a`) are
**hosted** → publish before `at_server`/consumers bump pins. `at_commons`, `at_chops`, and `at_auth` all
live in this monorepo as workspace packages (`packages/at_commons`, `packages/at_chops`, `packages/at_auth`);
only the atServer implementations are separate repos. ⚠️ **Caution:** workspace resolution wires these as
path deps locally and in CI, so a hosted dependency-floor violation (a consumer pinning an unpublished
`at_chops`/`at_auth`/`at_commons` version) is **masked** — it resolves fine against the workspace source but
would fail a real `pub get` off pub.dev. Publish/floor checks must validate the floors explicitly, not lean
on a green workspace build.

The graph uses **`RF-SRV`** and the **single-key `SS-3`** — the 1:1:1 shape. The rationale for the
substrate node structure is recorded in [decisions.md](decisions.md).

---

## 3. Phase A — PQ primitives & enrollment key (P-1, P-2, P-3)

### 14.37 The `0x01` seal version, removed outright

Closed 2026-08-18. [Ruling 110](decisions.md#110-the-0x01-seal-version-is-retired-stop-emitting-before-removing-2026-08-18)
retired the version and is amended in place with the reasoning below; this
entry is what the work turned out to be.

**Why one commit rather than the ruled two.** The staged order — stop emitting,
then remove — protects records already sealed under `0x01`. There are none that
matter, and for a stronger reason than "nothing outside this tree holds one":
the `nskey` subsystem that writes the durable, never-cleaned-up `__ck`
conveyance **does not exist on `trunk`** (0 files against 38 on this branch,
measured against a 2874-file listing), so no published build can create one.
The only `0x01` a published 3.14.0 can write is a pairwise `__ssenv` envelope,
and those carry `envelopeTtl = Duration(days: 7)`. Staging would have bought
nothing and left a window in which something could still emit one.

**⚠️ The row's commit 1 was mis-specified, and the error is worth keeping.** It
read *"drop `xWingHpke` from `SecretSharingAlgos.suites` … and leave it in
`openableSuitesFor(xWing)` so a holder still advertises that it can open one"*.
Both halves were backwards:

- **Emission does not read `suites`.** Both seal sites take their sender
  preference from `openableSuitesFor` — `nskey_provider.dart`'s
  `_sealVersionFor` and `pairwise_secret_sharing.dart`'s `sendEnvelope`. The
  prescribed edit would have changed nothing about what gets emitted.
- **The advertisement partly does.** `openableSuitesForAll` iterates `suites`,
  so `key_package.dart` and `nskey_key_ring.dart` derive through it while
  `published_nskey_key_ring.dart` calls `openableSuitesFor` directly. The edit
  would have narrowed three advertisement sites and left two — and that list
  reaches the wire on `enroll:request`, pinned as a raw literal.

The cause is legible: `openableSuitesFor` served both roles and **had no
dartdoc of its own**. The block describing it ran into the next function's with
no blank line between, so it attached to `bestSuiteBetween` and the sentence
that would have stopped both seal sites using an advertisement list as a sender
list was one member away from where anyone would look. That is repaired, and
the doc now says outright that it is an advertisement list.

**What went.** `xWingHpke` and its wire id, the `0x01` row of at_chops'
`_versions`, `_SealVersion.custom` with its `suiteLabel` and `_customAead`, the
custom branch of `_deriveKeyAndNonce` and the `_u8`/`_concat` helpers only it
used, `pq_seal_conformance_test.dart` and its 95-row `pq_seal_v1.json`.
`pqSealDefaultVersion` moved to `0x02` rather than being deleted: removing a
public const from at_chops is a separate API decision, and nothing reads the
default because `pqSealToBase64` makes `version` required.

**What changed shape rather than going away.** Two tests that asserted the
`0x01` fallback now assert the refusal that replaces it, against the same
fixtures — `pairwise_secret_sharing_test.dart` and `nskey_kem_selection_test.dart`
— and the refusal is asserted by its message, which names both suite lists.
`seal-spec.md` lost the ~200 lines specifying `0x01` and became the Atsign
envelope around RFC 9180. UC-A4.6's title said *"an absent list means the
original"*; an absent list has been refused at the parse since
`legacyNskeySuites` was deleted, so that title was already false and is now
about no-overlap instead.

**The consequence, stated plainly.** `trunk`'s `suites` is `[xWingHpke]` alone,
so a current build and a published 3.14.0 build share no construction and
cross-version secret sharing refuses rather than downgrading. Intended under
`@experimental`, and loud: both seal sites throw.

### P-1 — at_chops 3.3.0: stateless core + HPKE — **SATISFIED (published 2026-06-23)** · at_chops · S
**Goal:** ship the publishable `at_chops` minor everything pins. **Done:** `at_chops` **3.3.0 was published
to pub.dev on 2026-06-23** (`pqSeal`/`pqOpen` HPKE + the stateless surface + `@Deprecated AtChopsImpl` shim).
The substrate is **no longer gated on a P-1 publish**.
**Builds on:** #1993 (landed).
**Deliverables → [design.md](../design.md)** (at_chops primitives): residual only — confirm the stateless
functional surface and the deprecated shim both pass every X-Wing/GCM/HKDF/HMAC vector byte-exact, and that
`pqSeal`/`pqOpen` reuse `AesGcm256EncryptionAlgo`/`HkdfSha256` (no `package:cryptography` re-import). No
further publish required for P-1; the 3.3.0 slot is live.
**Acceptance → [acceptance.md](../acceptance.md):** all vectors green via both surfaces; `pqSeal` round-trip /
tamper→`authFailure` / info-aad-mismatch green; downstream construction sites compile unchanged.
**Effort:** S (residual confirmation).
**Watch-outs:** the `pqSeal` signature is frozen and shipped — downstream tracks compile against the
published 3.3.0 surface. Don't break the deprecated sync verify path.
**coversD1:** D1-S S1 + D1-A.

### P-2 — at_chops: wire `mldsa65` into the verification branch; publish with the 3.4.x slot · at_chops · M — **SATISFIED (published 2026-07-17)**
**Goal:** the one missing ML-DSA verification branch (the enum member + algo classes already ship in 3.3.0).
**Done:** the `_getVerificationAlgorithm` `mldsa65` branch **merged to trunk 2026-07-06** (issue #2050 /
PR #2056), folded into the 3.4.0 slot per the 2026-07-06 decision; #2039 (AES-GCM FFI) merged into the same
slot on 2026-07-09. **`at_chops` 3.4.0 was published to pub.dev on 2026-07-17**, closing the publish
residual — `at_server` can bump its pin in SS-3, and the at_chops publish no longer gates IS-1.
**Builds on:** — (independent root; parallel to P-1).
**Deliverables → [design.md](../design.md)** (at_chops primitives, ML-DSA): add an `mldsa65` branch in
`_getVerificationAlgorithm` returning `MlDsa65PureDartAlgo()` (no `DynamicLibrary` in `AtChopsImpl` — do
**not** claim FFI-when-available); no new `SigningAlgoType` member, no new algo class; publish in the new
minor. **The 3.4.0 slot assembled on trunk and published 2026-07-17:** #2030 (the `at_chops_ffi` barrel +
`AtPqc` auto-resolver + `AtSignatureAlgorithm` classes) **merged to trunk 2026-07-03** (+ #2046
review-fixes) and bumped `at_chops` to 3.4.0 under the one-time semver exemption; P-2's
`_getVerificationAlgorithm` `mldsa65` branch (#2056) and #2039 (AES-GCM FFI, merged 2026-07-09) folded into
that same 3.4.0, which then shipped. Those FFI PRs realise the **FFI-auto-resolve-default** policy
(FFI when available, pure-Dart fallback, WASM forces pure-Dart — ruling in [decisions.md](decisions.md)); they
are **in D1 scope**, on the at_chops track. **Scope note (2026-07-03 ruling):** auto-resolve applies to the
`AtPqc` accessors (`AtPqc.xWing`/`AtPqc.mlDsa65`, including their keygen); key generation through the
web-safe barrel's key pair classes (`XWingKeyPair.generate`, `MlDsa65KeyPair.generate`,
`AtChopsUtil.generate*KeyPair`) is pure-Dart by construction — those exports must stay out of the
`dart:ffi` import graph or `dart compile js`/wasm breaks for web consumers. Both backends are
wire-compatible, so pure-Dart-generated keys work with the FFI backends and vice versa.
**Acceptance → [acceptance.md](../acceptance.md):** **algorithm-level** sign/verify (true) + tamper (false);
rsa/ecc/pkam unchanged. Do **not** assert end-to-end `AtChops.verify(mldsa65)` — the deprecated sync path
doesn't await the async ML-DSA verify.
**Effort:** M.
**Watch-outs:** historical — the `mldsa65` verify branch went into the then-unpublished 3.4.0 (opened on
trunk via #2030) rather than a fresh minor; that slot has since published. **ML-DSA APKAM auth is
retained** — the
1:1:1 simplification does not drop ML-DSA: the at_chops `mldsa65` verify branch (this project), the
at_commons pkam `signingAlgo` literal (folded into SS-1a's publish), and the server `_getSigningAlgoType`
branch reading the **record** `signingAlgo` together make it work.
**coversD1:** D1-F DEP3-prep.

### P-3 — PQ enrollment-conveyance key `public:pqpublickey` + X-Wing-preferred enrollment wrap · at_client, **at_auth**, at_chops · M
**Goal:** close the harvest-now-decrypt-later hole in enrollment conveyance; publish the root PQ key.
**Builds on:** P-1 (`pqSeal`). **No atServer change** (the server stores `encryptedAPKAMSymmetricKey`
opaquely).
**Deliverables → [design.md](../design.md)** (pqpublickey root key lifecycle): publish
`public:pqpublickey@<atSign>` (root, **never** `publickey.pq`); new enrollees prefer X-Wing-wrapping
`apkamSymmetricKey` to it; approvers accept RSA **or** X-Wing. ⚠️ the RSA-wrap lives in **at_auth** — add
at_auth to scope and bump its `at_chops` pin to `^3.3.0`. Freeze the `pqpublickey` **name + create-once
contract** as an interface-first artifact shared with SS-4 (which owns the create/seed/serve/pull lifecycle).
**Acceptance → [acceptance.md](../acceptance.md):** enroll/approve conveys `apkamSymmetricKey` X-Wing-sealed
(nothing RSA in the path) with RSA fallback; functional enrollment test green; the published `pqpublickey`
is fetchable. Do **not** attach full UC-A2.1 here (its "convey the nskey private per-APKAM via `__ssenv`" half
is SS-2/SS-4), and do **not** claim cold-start CK *usage* (that's B-1).
**Effort:** M.
**Watch-outs:** see **Open decision #A** (P-3 publishes/prefers `pqpublickey` before SS-4 owns its
lifecycle); P-3's acceptance can only prove "published + fetchable," not cold-start serve/pull.
**coversD1:** D1-A enrollment-conveyance key; cold-start target for B4.

---

## 4. Phase S — Structural enablers / key management (S-1, S-2, S-3, S-5, S-6, KF-1)

**Structural facts (stated once).** (1) `CryptoContext` is `{atClient}`, so the additive `keys` field has
**nothing to deprecate**; (2) at_auth's `AtKeys` is **extended in place** — additive PQ-safe methods with the
legacy key fields/methods deprecated (no new holder class) — and `AtKeysIo` gains runtime persistence
(ratified 2026-07-06, #2045 — see [decisions.md](decisions.md)); (3)
`CryptoRuntime` resolves against the live `AtClientPreference.crypto`, and cached-client reuse adopts the
new config (there is no `CryptoRegistry`).

**Parallelism fact (stated once)** — `S-1`/`S-2`/`S-3` do **not** gate Wave-2 substrate work; the substrate's
`P-1`/`pqSeal` publish gate is **already satisfied** (at_chops 3.3.0, published 2026-06-23), leaving the SS-0
baseline (PR #2037) as its prerequisite (see [section 10](#10-cross-cutting-publish-gates-critical-path-wavesparallelism-testing)).

### S-1 — at_auth: extend `AtKeys` in place (additive PQ methods, deprecate legacy) + `AtKeysIo` runtime persistence (API only); publish 3.3.0 · at_auth · M — **SATISFIED and PUBLISHED — at_auth 3.3.0 is on pub.dev (re-verified 2026-08-08); no residual.** Consequence: **at_auth's next version is already open** in-tree and unpublished (opened 2026-08-03, `936241d8f`), so a further at_auth change folds into that heading rather than opening a new one. ⚠️ That heading was **3.4.0-rc1 until 2026-08-22**, when the keyfile rename made it breaking and `96025e46c` renamed it **4.0.0-rc1** — a major
**Goal:** extend the existing `AtKeys` in place so it holds every key (per-enrollment AND per-APKAM) via
additive PQ-safe accessors while the legacy key fields deprecate; interface-first.
**Builds on:** at_auth `AtKeys`. Additive only; gates nothing in Wave 2.
**Deliverables → [design.md](../design.md)** (structural design: extend `AtKeys`/`AtKeysIo` in place): keep the
`AtKeys` class hierarchy as-is and extend it **additively** with PQ-safe methods (`addKey`/`retireKey` over
typed `CryptographicMaterial`; **retire, never remove** — forward-only status, 2026-07-17 ruling), **deprecating**
the legacy key fields/methods (they stay for back-compat so call sites migrate over time); extend `AtKeysIo`
with **runtime persistence** — the single whole-state **`flush()`** (supersedes the `append()`/`save()`
working names, 2026-07-17 ruling), safety-checked via `AtKeysAssurance.validateMapUpdate`, atomic
(temp + rename, `.bak` kept), with a throwing default impl so existing implementers compile unchanged — so
it stays the single contact point keeping runtime `AtKeys` objects and the persisted keyfile in-line.
Concrete impls (`InMemoryAtKeysIo`, the keychain/file `AtKeysIo`) remain `AtKeysIo` implementations.
(Supersedes the earlier `WritableAtKeys` holder, #2045 — ratified 2026-07-06, see
[decisions.md](decisions.md).)
**Acceptance → [acceptance.md](../acceptance.md):** existing onboard/auth suites green; the extended `AtKeys`
PQ add→read→retire (material never removed; legacy fields still readable via the deprecated accessors);
`InMemoryAtKeysIo` round-trip (persistent round-trip proven once **S-3** wires the stores); unknown
`role`/`algorithm` tokens round-trip unmodified.
**Effort:** M.
**Watch-outs:** ⚠️ **version** — resolved 2026-07-17: at_auth 3.1.1 published, then **3.2.0 was consumed by
the validateAtServer network-timeout release**; S-1 ships as **3.3.0** (Open decision #D closed). The
at_chops 3.4.x prerequisite (hashing-algo barrel exports) is satisfied — 3.4.0 published 2026-07-17.
**Publish state:** S-1 landed via PR #2047 (+ #2080 tweaks). **`at_auth 3.3.0` is published stable on
pub.dev** — the old rc1 → stable gate is **closed**, so S-6 (consumer bumps) and SS-2's at_auth work have
the stable version they needed to pin against. **at_auth 4.0.0-rc1 is open in-tree and unpublished**
(`936241d8f`, 2026-08-03; the heading read 3.4.0-rc1 until `96025e46c` on 2026-08-22 made it a major) carrying `CryptographicMaterialAlgorithm.mlKem1024` and the `.atKeys` passphrase-salt fix, so
what ON-1 adds to at_auth — `mintLegacyMaterial` — folds under that heading.
*(This paragraph asserted the rc1 gate for five days after the heading above was corrected, and a resume
summary copied the body rather than the heading. A superseded claim gets deleted, not left standing beside
its correction.)*
**S-2 carries a sibling residual** (its `CryptoContext.keys` merged after `at_client 3.14.0` published), so
both structural enablers are merged-but-unpublished and clear together on the next release round.
**coversD1:** D1-S S2.

### S-2 — at_client: `CryptoContext.keys` additive field (interface-first only) · at_client · S (≈1 PR) — **SATISFIED on trunk (2026-07-17); residual = the at_client publish**
**Goal:** the tiny field the data path compiles against.
**Done:** the seam landed with #1930; PR **#2076** threaded the `AtKeysIo` through `CryptoContext` on
2026-07-17, completing the additive field.
⚠️ **Merged but not yet published.** #2076 merged at 18:20Z on 2026-07-17, *after* `at_client 3.14.0`
published at 16:02Z the same day, and the 3.14.0 changelog does not mention it. The `CryptoContext.keys`
field therefore sits on trunk **unreleased** — a consumer pinning a hosted `at_client` cannot compile
against it yet. Downstream projects that need the field from a published package (rather than through
workspace path resolution, which masks the gap locally and in CI) must sequence after the next `at_client`
release.
**Builds on:** #1930 + S-1's extended `AtKeys` / injected `AtKeysIo`.
**Deliverables → [design.md](../design.md)** (CryptoProvider seam): add an `AtKeysIo keys` field to
`CryptoContext` (additive) — the provider seam is injected the `AtKeysIo` (the key source) and yields the
extended `AtKeys`; `CryptoRuntime` threads it into provider calls (ratified 2026-07-06, #2045 — see
[decisions.md](decisions.md)).
**Acceptance → [acceptance.md](../acceptance.md):** existing crypto/legacy round-trips green; behaviour-neutral
(no wire/stored-value change); Mode-B regression retained.
**Effort:** S.
**Watch-outs:** ⚠️ **Scope cut** — keep ONLY the additive field; **defer** migrating `LegacyCryptoProvider`
to read from `context.keys` (legacy pulls remote `plookup`s + `atChops` cipher ops the 6 static fields
can't supply). This plan keeps `LegacyCryptoProvider` reading its own sources (additive-field-only) — see
Open decision #E in [decisions.md](decisions.md).
Resolve where `context.keys` is sourced at construction (overlaps S-3).
**coversD1:** D1-S S5.

### S-3 — at_client/at_auth: updatable `.atKeys`/keychain via the injected `AtKeysIo` · at_client, at_auth, at_client_flutter · L — **PARTLY LANDED 2026-08-08**
**Landed so far, and the two things it turned out to be about:**
- **The keychain is a real store.** `KeychainAtKeysIo` implemented `read`/`write`
  only, so `flush` fell through to the interface's throwing default — on Flutter,
  which *defaults* to that store, filing an nskey private or a signing-root
  private threw `UnimplementedError`. It now replaces the atSign's entry under
  the same never-lose assurance the file store gets. Two silent-loss bugs went
  with it: `write` appended unconditionally to a list `read` scans
  front-to-back, so a second write left the newer keys permanently unreachable;
  and an entry carrying its atSign under the legacy `name` metadata key threw a
  `TypeError` from `getAllAtsigns` and survived `removeAtsignFromKeychain`.
- **`WrittenAtKeysIo.update`** — read, mutate and persist as one operation, with
  `FileAtKeysIo` holding its keyfile lock across all three steps. The
  hand-rolled `read` → mutate → `flush` that every consumer used loses material
  whenever two of them overlap, and a client's start overlaps two by
  construction: `_seedNamespaceKeys` and `_fileConveyedKeysAndAnchor` are
  sibling **unawaited** tasks, each reading the keyfile, adding its own material
  and flushing. Whichever flushed second was refused by assurance — correctly —
  and its key material was gone. `PqSigningRoot` and `NskeyPrivateFiling` are
  migrated; the control arm proving the loss is in
  `at_auth/test/at_keys_update_test.dart`.

**Ruled: the self-encryption-key re-wrap is NOT built, because it has no
operator.** The watch-out below is accurate — `flush` compares the four
self-encrypted legacy fields as *ciphertext* (both sides are the at-rest
document), and it works today only because `generateIVLegacy()` is sixteen zero
bytes, making AES-CBC re-encryption byte-identical. A re-wrap changes five
compared values at once and fails assurance. But **no code path anywhere changes
`defaultSelfEncryptionKey` on an existing keyfile**: the only mutator sets it
during enrollment approval, on a file that does not yet exist. Building the
re-wrap now would be a mechanism with no party that operates it. It belongs to
whichever project first needs one — **KF-1** (at-rest protection of the PQ
privates), whose restore flow already needs an assurance override for the
inverse case. Recorded here so it is a decision rather than an omission.

**Still owed:** the migration test on a v(N-1) fixture, the keychain round-trip
on a real device (at_client_flutter's tests mock the platform channel, and this
repo has no integration_test harness), and the `LocalKeystoreAtKeysIo`
existence/routing call — still "not needed at this time".

**Goal:** durable, updatable key-storage homes (bootstrap→file/keychain, distributed/rotating→keystore,
ephemeral→memory). Stores are **dumb** — convergence stays in the substrate.
**Builds on:** S-1's extended `AtKeysIo` runtime-persistence API.
**Deliverables → [design.md](../design.md)** (key stores): make `FileAtKeysIo` updatable (re-wrap the
self-encryption key on rewrite, atomic write + backup); compose the extended `AtKeys` (via its injected
`AtKeysIo`) at AtClient construction; cover the keychain store, which `flush()` alone does not reach.
`LocalKeystoreAtKeysIo` over the 5.x keystore is **out of scope** (2026-07-17 ruling).
**Acceptance → [acceptance.md](../acceptance.md):** post-onboarding key add persists + survives close/reopen;
ephemeral stays in-memory; **migration test** on a v(N-1) `.atKeys`/store fixture (backend is **Hive**
today, not SQLite — keep the test backend-agnostic; name any legacy box/table explicitly); a **keychain
updatable round-trip on mobile/desktop**; functional onboard+add+read-next-run green.
**Effort:** L.
**Watch-outs:** file rewrite must re-wrap the self-enc key or it's unreadable next run — and note
`flush`'s `validateMapUpdate` compares the legacy fields as ciphertext, so a self-enc-key re-wrap fails
assurance as-built; S-3 needs an explicit re-wrap path. `LocalKeystoreAtKeysIo` is **not needed at this
time** (2026-07-17 ruling, [decisions.md](decisions.md)) — decide its existence/routing here, and any store
holding CK-class material must support eviction (B5a), not inherit `flush`'s never-lose contract. Run the
integration suite at every commit boundary (resource lifecycle). Does **not** gate the substrate.
**coversD1:** D1-S S2/S3.

### S-5 — at_auth 4.0.0: WASM barrel split · at_auth · L  *(parallel, off the GA critical path)* — **DONE 2026-08-22.** `at_auth_io.dart` carved; nothing reachable from `at_auth.dart` imports `dart:io`, guarded by `packages/at_auth/test/wasm_barrel_test.dart`, which was red on the one export it names before that export went. Residual: **the publish**, and the transitive `dart:io`/`dart:ffi` reach through at_lookup/at_chops, which this deliberately does not gate on
**Goal:** make the at_auth core WASM-safe (the one breaking major in the program).
**Builds on:** S-3 (so the extended `AtKeys`/`AtKeysIo` + updatable stores bake on 3.3.0 before the breaking cut).
**Deliverables → [design.md](../design.md)** (WASM barrel): move `FileAtKeysIo` + the `dart:io` socket probe
to a new `at_auth_io.dart` barrel; drop the `atKeysIo ??= FileAtKeysIo()` default (require injection);
registrar on `package:http`; publish 4.0.0.
**Acceptance → [acceptance.md](../acceptance.md):** ⚠️ **narrowed** — assert the *at_auth-owned* sources
reachable from `at_auth.dart` no longer import `dart:io` and the default is gone. Do **not** gate on a true
`dart compile wasm` of the core (it still transitively reaches `dart:io`/`dart:ffi` via `at_lookup`/`at_chops`
— those WASM splits are a **separate effort out of the D1 crypto program**, the `wasm-port`). CLI/flutter
importing `at_auth_io.dart` compile + auth functional green (post-**S-6**).
**Effort:** L.
**Watch-outs:** `FileAtKeysIo` never leaves at_auth. **at_auth 4.0 (structural/WASM) is a different major at
a different time from at_client 4.0 (R-2, the posture flip).**
**coversD1:** D1-S S4.

### S-6 — Consumer constraint bumps onto at_auth `^4.0.0` · at_client, at_onboarding_cli, at_client_flutter, **tests/at_functional_test, tests/at_end2end_test** · M — **DONE 2026-08-22**, at the candidate floor `^4.0.0-rc1` rather than `^4.0.0` (see 14.49.2; it reverts when these publish). Consumers take `FileAtKeysIo` from `at_auth_io.dart`; `at_client` needed no change, and `packages/at_chat_flutter/example` is deliberately left at `^3.0.0` — it has no path override, so a candidate floor would strand it
**Goal:** consumers adopt the breaking at_auth major.
**Builds on:** S-5. Publish in dep order (at_chops → at_auth → at_client/onboarding/flutter → at_cli_commons).
**Deliverables → [design.md](../design.md)** (WASM barrel consumer adoption): consumers adopt `at_auth ^4.0.0`,
importing `FileAtKeysIo` from `at_auth_io.dart` with explicit injection. ⚠️ the two **test packages pin
at_auth directly** — include them; `at_cli_commons` is a **transitive-only** bump (no direct at_auth dep,
no FileAtKeysIo use).
**Acceptance → [acceptance.md](../acceptance.md):** each consumer + both test packages compile and pass against
`^4.0.0` with explicit injection; onboarding functional green.
**Effort:** M.
**Watch-outs:** sweep every inline `FileAtKeysIo()` site; `example/pubspec.yaml` `dependency_overrides`
needs at_auth added; use `melos bootstrap`.
**coversD1:** D1-S S6.

### KF-1 — `.atKeys`-at-rest protection + backup/restore · at_client, at_auth, at_client_flutter · L — [#2129](https://github.com/atsign-foundation/at_client_sdk/issues/2129)  *(new D1 scope, off the GA critical path — parallel)*
**Goal:** protect the PQ private material in the keyfile at rest and define a backup/restore story (including
the stale-backup case). Off the GA critical path — runs in parallel.
**Builds on:** S-3 (updatable `.atKeys`). Additive; gates nothing on the GA critical path.
**Deliverables → [design.md](../design.md)** (keyfile at-rest protection + backup/restore): encrypt the PQ
private material at rest in the keyfile — the **X-Wing key-package private** and the **ML-DSA APKAM private**
— alongside the existing key material; define the keyfile **backup/restore** flow, including the
**stale-backup** case: a restored backup whose enrollment was **capped/expired by a retrofit** (RF-SRV) must
be detected and handled rather than silently authenticating with a dead enrollment.
**Acceptance → [acceptance.md](../acceptance.md):** PQ privates unreadable at rest without the wrapping key;
backup→restore round-trip on a live enrollment; a restored **stale** backup (enrollment capped/expired) is
detected (re-retrofit or clear error), not a silent auth against the aged-out enrollment.
**Effort:** L.
**Watch-outs:** the stale-backup case couples to RF-SRV's expiry cap — a backup taken before a retrofit
carries an enrollmentId the server has since capped; restore must reconcile against the live enrollment state.
Restoring an older backup over a newer keyfile is **rejected by `flush`'s `validateMapUpdate`** (materials
missing / statuses moving backward) — the right default, so KF-1's restore flow needs an explicit override
path, and stale-backup detection is mandatory, not optional.
**coversD1:** D1-S keyfile-at-rest + backup/restore (new scope).

**NoPorts uptake (pointer).** NoPorts is the roadmap's finish line, yet this plan carries no NoPorts work
package. NoPorts adoption of the PQ-safe data path is **tracked in the NoPorts repo, out of this plan's
lane** — sequenced after B-1 (a PQ-capable `at_client` reader/writer) is available. If a NoPorts-side WP is
later pulled into this lane, slot it after B-1.

---

## 5. Phase SS — Secret-sharing substrate (SS-1a, SS-1b, SS-1c, SS-2, SS-3, SS-4)

The `SS-*` projects define the secret-sharing substrate work; the substrate design lives in
[design.md](../design.md) [section 2](../design.md#2-subsystem-b--the-secret-sharing-substrate-wp-ss). **SS-0 landed the substrate baseline** (PR #2037, merged 2026-07-17) — SS-1c /
SS-2 / RF-1 all presuppose that code, and it is now on trunk.

**Shared substrate fact (stated once).** **pull** (`requestSecret`) and **push**
(`pushSecretToNamespaceMembers`) are **dual facets of one substrate**: the same `__ssenv` envelope sealed
to a key package via `pqSeal`, the same gated `enroll:listns` discovery, the same `SecretStore`
and `putIfNewer` ordering. The mechanics (kpid addressing, the `__ssenv` envelope shape, sign/verify,
`SecretStore`, push/pull primitives, the `enroll:listns` verb + `EnrollParams.metadata`, the
atServer enrollment record + the authenticated self-retrofit flow + expiry copy/cap) live in
[design.md](../design.md). The given/when/then (UC-A2.x / A3.2 / B5.x) lives in [acceptance.md](../acceptance.md).

**Parallelism fact (stated once).** The substrate's publish gate — **P-1/`pqSeal`** on `at_chops` 3.3.0 — is
**already satisfied** (published 2026-06-23); its remaining prerequisite is the **SS-0 baseline** (PR #2037)
on trunk. It does **not** gate on S-1/S-2/S-3.

**Substrate design facts (stated once; rationale in [decisions.md](decisions.md)):**

1. **There is no `enroll:metadata` verb** — the key package rides an opaque `Map<String,dynamic>
   EnrollParams.metadata` on `enroll:request` (JSON tail; **no grammar change**); the server stores/returns
   it; **no post-enrollment metadata write, ever**.
2. **`enroll:listns` returns the flat shape** `[{enrollmentId, access, apkamPubKey, metadata}]`
   — **no nested `apkam[]` array**.
3. **The enrollment record stores a SINGLE `apkamPublicKey` + a `signingAlgo`** (`rsa2048|mldsa65`);
   **never >1 keypair**. PKAM verify selects RSA vs ML-DSA from the **record** `signingAlgo`
   (**record-authoritative**, not the client-supplied wire value); legacy null → `rsa2048`.
4. **One nskey keypair per `(atSign, namespace)`** — the recipient key for both directions (Alice
   encapsulates her own CKs to it; external senders encapsulate CKs to it when sharing with her). Its
   public half is **published eagerly** at mint to `public:__nskey.<ns>@alice` — an APKAM-signed
   `{v, createdAt, keys:[…], suites}` envelope, **mutable** (rotation overwrites it, serialised by the short-ttl
   immutable lock `_nskeylock.<ns>@alice`), and unscannable by virtue of the leading underscore while
   still served on an exact `plookup` ([decisions.md](decisions.md) section 13). Its private — a KEM
   private that **decapsulates** CKs, never decrypts application data — is conveyed per-APKAM as a
   Secret over the substrate, and earlier generations are retained, addressed by `nskeyKid`.
5. **appMetadata carries `ns`** — the value's own namespace — **and `ckNs`** on a data value, naming where
   the content key lives ([decisions.md](decisions.md) section 19). `ns` exists because `AtKey.fromString`
   splits at the **last** dot, so a multi-segment namespace is unrecoverable from the wire string; it is
   also what the layer-3 AAD binds. (This fact previously read "appMetadata carries NO `ns` field", which
   the nested-namespace ruling reversed.) See B-1 in
   [section 6](#6-phase-b--the-nskey-data-path-b-1-the-d1-centrepiece).

### SS-0 — land the WP-SS substrate baseline · at_client · M — **SATISFIED (merged to trunk 2026-07-17)**
**Goal:** get the WP-SS secret-sharing substrate code onto trunk — the foundation SS-1c / SS-2 / RF-1
presuppose.
**Builds on:** #1930 + P-1 (`pqSeal`, published 3.3.0).
**Done:** **PR #2037 merged to trunk on 2026-07-17**, in the 1:1:1 / flat `listns` / no-write-path shape
(reworked via #2043 — single `apkamPublicKey` + `signingAlgo`; flat discovery roster; no
`registerKeyPackage` / `enroll:metadata` write path). It shipped in `at_client 3.14.0` (published
2026-07-17) as an experimental surface. This is the `__ssenv` envelope, `SecretStore`, `putIfNewer`
ordering, `kpid` addressing, and the push/pull primitives the later SS projects wire up.
**Acceptance → [acceptance.md](../acceptance.md):** substrate unit suite green; the baseline compiles in the
1:1:1 shape with no write-path residue.
**Effort:** M.
**Watch-outs:** SS-1c / SS-2 / RF-1 cite PR #2037 as "already landed" — that prerequisite is now met.
**coversD1:** D1-F substrate baseline.

### SS-1a — at_commons enroll grammar: `EnrollParams.metadata` + flattened `listns`; publish 5.12.0 — **SATISFIED (at_commons 5.12.0 published 2026-07-04; grammar on trunk via #2040)** · at_commons · M
**Status:** SATISFIED — landed on trunk via #2040 (2026-07-04, with #2044 stacked in); at_commons 5.12.0 published to pub.dev.
**Goal:** publish the grammar the new enroll verbs need before any server can parse them.
**Builds on:** — (root). The key package rides `EnrollParams.metadata` (no grammar change); there is no
`enroll:metadata` op.
**Deliverables → [design.md](../design.md)** (enroll verb grammar / `EnrollParams.metadata`): add the
`listns` op (inner alternative inside the single `(?<operation>)` group, leftmost-first before
`list`) + its `listNamespace` segment. Add `metadata` (opaque map) and `signingAlgo` (`rsa2048|mldsa65`)
fields to `EnrollParams` + the `EnrollVerbBuilder` cascade + `.g.dart` regen. Document the **flattened**
`listns` shape `[{enrollmentId, access, apkamPubKey, metadata}]`. Also widen the **pkam-verb**
`signingAlgo` literal (`ecc_secp256r1|rsa2048` → add `mldsa65`, consumed by the server at auth time — folded
into this publish, #D). Bump 5.11.0 → **5.12.0** + publish.
**Acceptance → [acceptance.md](../acceptance.md):** `listns` parses (no `metadata` op); `EnrollParams`
round-trips `metadata`+`signingAlgo`; empty `metadata` dropped; pkam regex accepts the ML-DSA literal.
**Effort:** M.
**Watch-outs:** re-confirm the at_commons pub.dev floor at execution (#D). `EnrollParams.signingAlgo` only
**records** the enrolled key's algo — it does not satisfy the pkam-verb literal (that's the same publish,
folded into this publish).
**coversD1:** D1-F DEP1 (flatten, commons) + DEP2 (`EnrollParams.metadata` replaces `enroll:metadata`) +
DEP3 (record `signingAlgo`).

### SS-1b — server: store/return `EnrollParams.metadata` + flattened `listns` + first live round-trip · at_secondary_server, at_server_spec · L — **SATISFIED (merged 2026-07-07)**
**Goal:** persist the opaque blob and serve the gated discovery roster.
**Builds on:** SS-1a (publish first).
**Done:** landed in `at_server` across **#2685** (the `enroll:listns` verb, verbatim enrollment `metadata`,
`_apsk` APKAM pubkey publication, merged 2026-07-07), **#2687** (alignment to the ratified WP-SS shape),
**#2696** (typed `EnrollParams` metadata/signingAlgo), **#2698** (functional tests for the `listns` roster
and enrollment metadata) and **#2710** (per-enrollment move scoping). The client obligation (SS-1c, #2084)
is now unblocked.
**Deliverables → [design.md](../design.md)** (atServer enrollment record): on `enroll:request`, persist
`enrollParams.metadata` + `signingAlgo` onto the enrollment record (`EnrollDataStoreValue` gains
`metadata` + `signingAlgo`; store a **single** `apkamPublicKey`). Add the gated `enroll:listns`
discovery (a new `_isAtLeastReadOnNamespace` gate) emitting the **flat**
`data:[{enrollmentId, access, apkamPubKey, metadata}]`; at_server_spec dartdoc; first live functional round-trip.
Also **keep `_apsk` present**: the atServer populates `public:_apsk.<eid>.<perEnrollmentApproved>@<atSign>`
from the record's `apkamPublicKey` (on approval / first authenticated use) rather than relying on the
client-side `publishPublicSigningKey`, and keeps its write-restriction — the presence + write-restriction
cross-tier property (design.md [section 2.4](../design.md#24-the-atserver-enrollment-record--ml-dsa-apkam-auth)) that both envelope and advertised-key verification depend on.
**Acceptance → [acceptance.md](../acceptance.md):** metadata stored verbatim + returned by `listns`;
**schema-migration test** (pre-`metadata`/`signingAlgo` record opens null, write round-trips); flat records,
≥r gate, approved-only, `*` wildcard; UC-A2.3 server discovery gate; an approved enrollment's `_apsk` is
fetchable without a client publish, and a cross-enrollment `_apsk` overwrite is refused; `runLocal.sh`
(compose-down, ≤180s) + **both** suites green.
**Effort:** L.
**Watch-outs:** ⚠️ the at_commons fields (SS-1a) must publish first; **the atServer-schema change must land in
the same release as the client**; check the enroll-record value-size limit accommodates a ~1KB key-package
blob; downstream client obligation = SS-1c.
**coversD1:** D1-F DEP1 (server) + DEP2.

### SS-1c — wire at_client to the live verbs + flattened parser · at_client, tests · M — [#2084](https://github.com/atsign-foundation/at_client_sdk/issues/2084) — **LANDED**
**Goal:** drive the live verbs and parse the flat shape.
**Landed:** the flat `listns` parser, and the advertised-key verification for **both**
keys — the published `nskey` (`ApkamSignedAdvertisedKeys`, proven cross-atSign live) and
the **key package** (`KeyPackageRegistration.signedKeyPackagePayload` /
`VerbEnrollmentDirectory`, unit-only). ✅ **The live drive landed** (checked 2026-08-16, plan 14.25).
`VerbEnrollmentDirectory` issues `enroll:listns:<ns>` at
`enrollment_directory.dart:143`, from **four production call sites** in
`pairwise_secret_sharing.dart`, and two live functional tests drive it —
`apsk_server_side_test.dart` and `nskey_rotation_live_test.dart`.
**Builds on:** SS-0 (substrate baseline on trunk) + SS-1b.
**Deliverables → [design.md](../design.md)** (`enroll:listns` client parser): rewrite
`VerbEnrollmentDirectory.listForNamespace` for the **flat** `[{enrollmentId, access, apkamPubKey, metadata}]`
shape (one `NamespaceMember` per enrollment, **singular nullable `metadata.keyPackage`** — no format-keyed
map, `KeyPackage.apkamId` from `apkamPubKey`). The key package rides `enroll:request` (SS-2); there is no
`registerKeyPackage` / `enroll:metadata` write path, interface decl, `register()` call site, or
`FakeEnrollmentDirectory.registerKeyPackage`. The `listForNamespace` dartdocs state the **1:1:1 single-key**
model. **Verify the advertised key package's APKAM signature** against the enrolling atSign's `_apsk`
(design.md [section 2.1](../design.md#21-kpid-addressing-__ssenv-envelope-signverify) *Advertised-key authenticity*) before trusting it — the same verify path same-atSign and
cross-atSign; reject an unsigned / wrong-signer package.
**Acceptance → [acceptance.md](../acceptance.md):** flat parse → `NamespaceMember` + decoded `KeyPackage`; a
signed key package verifies against `_apsk`, a tampered / wrong-signer one is rejected; **no
code path issues `enroll:metadata`**; the test-consumer sweep migrates all three suites off the `registered`
seam to a 1:1:1 seeding seam; a client-driven functional round-trip.
**Effort:** M.
**Watch-outs:** the `listForNamespace` parse unit test already exists (landed with the SS-0 baseline, PR
#2037) — don't duplicate it. Clear the test's own `.atKeys` and gitignore it.
**coversD1:** D1-F DEP1 (client parser) + DEP2 (write path removed).

**Progress (2026-08-03, `gkc-pq-d1-spike`).** **All six implementation steps are landed**, with the
whole chain proven live in `tests/at_functional_test/test/enrollment_key_package_live_test.dart`:
the key package rides `enroll:request`, comes back on the record, verifies against the `_apsk` the
atServer publishes on approval — **carrying no `enrollmentId` claim**, which is ruling 5 proven on
the wire rather than argued from code — and approving seals this atSign's secrets to it, checked by
reading the `__ssenv` envelope remotely so a local-only pass cannot fake it.

⚠️ **The published `atsigncompany/virtualenv:vip` image does not store `EnrollParams.metadata`**
(verified 2026-08-03 with a probe whose marker appears only inside `metadata`). at_server trunk
persists it — that landed with SS-1b on 2026-07-07 — but vip lags trunk until a canary→prod
promotion, so the key package cannot reach the enrollment record against vip at all. The live tests
therefore run against a locally built `at_virtual_env:local`. **Before SS-2 opens a PR**, confirm vip
has been promoted and re-run the pack against it; CI uses vip, and the functional rails are
temporarily pointed away from it.

*Superseded progress note:* two of the six steps were landed at the time of writing:
the keys-sourced envelope signer (`signEnvelope` / `verifyEnvelope` take key material as an
argument, both signing mixins moved onto it, all five D1 consumers migrated), and
`AtEnrollmentRequest.metadataBuilder` in at_auth 4.0.0-rc1. Still to do: build and sign the key
package inside the callback; the four-way key-package status on `NamespaceMember`;
`Enrollment.metadata` plus conveyance in `EnrollmentServiceImpl.approve` with the Flutter and
CLI paths routed through it; and the live functional test over the whole chain
([decisions.md 20](decisions.md#20-ss-2-how-the-key-package-reaches-an-enrollment-and-how-conveyance-fires-2026-08-03)
ruling 10).

### SS-2 — substrate wired into AtClient + server wake-up; key-package-in-request (new-device conveyance only) · at_secondary_server, at_client, at_auth, at_commons · L — [#2085](https://github.com/atsign-foundation/at_client_sdk/issues/2085)
**Goal:** the first production call sites + the server-side wake-up + the new-device conveyance path.
**Builds on:** SS-1c.
**Deliverables → [design.md](../design.md)** (substrate production wiring + server wake-up): DEP4 `__ssenv`
update-put auto-notify (drop the rethrow; update-path only) + flip client self-wake-up off. **Production
wiring:** re-key the facade Expando to `(AtClient, enrollmentId)` (+ `enrollmentId`
on `forClient`); the X-Wing key package — **APKAM-signed via `wrapAndSign`** (design.md [section 2.1](../design.md#21-kpid-addressing-__ssenv-envelope-signverify)
*Advertised-key authenticity*) and placed at the singular `metadata.keyPackage` — rides into `enroll:request`
as the opaque `EnrollParams.metadata` (built by an at_client orchestrator *above* at_auth; at_auth ferries,
never interprets). **Conveyance is the
NEW-DEVICE approver path only:** an at_client approve-wrapper fires `shareAllSecretsWithEnrollment` after
at_auth's `approve` (seals an `__ssenv` envelope to the new device's key package). The **auto-approved
self-retrofit** (RF-2b/RF-SRV) needs **no conveyance** — the retrofitting client already holds its own
secrets locally. **ML-DSA APKAM auth:** the at_chops
verify branch (P-2) + the at_commons pkam `mldsa65` literal (in SS-1a's publish) + the server
`_getSigningAlgoType` ML-DSA branch reading the record's `signingAlgo`.
**Acceptance → [acceptance.md](../acceptance.md):** one value-less `__ssenv` self-notify on update (none on
delete; survives an enqueue throw); `forClient` distinct per `(AtClient, enrollmentId)`; a new-device
`enroll:request` carries the opaque key package, the approver reads it and `approve` seals an `__ssenv`
envelope + fires `shareAllSecretsWithEnrollment`; **no `enroll:metadata` command ever issued**; both suites.
**Effort:** L.
**Watch-outs:** ⚠️ **there is no atServer *schema* change left in SS-2** — that watch-out was inherited from
SS-1b, where it was true, and is stale here (verified against `at_server` @ `3f77a3a0`, 2026-08-03). The key
package rides inside `EnrollDataStoreValue.metadata`, which SS-1b already stores verbatim and returns from
`listns`; the field's own dartdoc already names `metadata['keyPackage']` and the 1:1:1 model, and
`enroll_verb_handler.dart` already persists `signingAlgo`. So the **key-package-in-request half is
client-only** and runs against today's atServer unchanged.
What the atServer genuinely still lacks is **behaviour, not shape**, and it is the smaller half:
(1) **`__ssenv` does not exist server-side at all** — the only occurrence in `at_server` is a comment in
`enroll_verb_handler.dart` — ⚠️ **checked 2026-08-16: even that comment is gone, so it is now zero
occurrences.** DEP4's update-put auto-notify remains unbuilt.

⛔ **The second item was FIXED and this entry did not say so.** It read: `_getSigningAlgoType`
(`pkam_verb_handler.dart`) branches on ecc and rsa2048 only, so a PQ-APKAM would be verified as RSA
and fail. That method **no longer exists**. `ApkamSignatureVerifier`
(`packages/at_secondary_server/lib/src/utils/apkam_signature_verifier.dart`) handles `mldsa65`,
verifies against the key **recorded on the enrollment** rather than the client-supplied token, and
carries its own test. That it was still written here as owed is why ML-DSA PKAM working live and
this paragraph could both be true at once and nobody reconciled them.
Also: ~1KB blob size limit; listener-before-trigger for the wake-up subscription.
**DEP4 is now deferred, not owed by SS-2** (ruled 2026-08-03). Investigating whether the
client-side wake-up is sufficient turned up the reason it *wasn't*: `sendEnvelope` put the
envelope local-first while the notify went straight out remote, so the nudge could outrun the
value and a sync-less recipient would sweep an atServer that did not hold the envelope yet.
That is fixed client-side by writing the envelope remote-first, which orders the two by
construction and needs no atServer change. DEP4 remains a genuine improvement — a server-side
auto-notify fires independently of the sender's SDK version or config — but it is now a pure
optimisation with no correctness argument behind it, and the client `sendWakeUpNotification`
default stays **true** until it lands.
**coversD1:** D1-F DEP4 + production wiring (new-device conveyance).

### SS-3 — substrate hardening + `signingAlgo` verify · at_secondary_server, at_client · M — [#2086](https://github.com/atsign-foundation/at_client_sdk/issues/2086) — **LANDED on `gkc-pq-d1-spike`** (client) **/ PR [at_server#2739](https://github.com/atsign-foundation/at_server/pull/2739)** (server, merged 2026-08-10 — ⚠️ this said **#2736** until 2026-08-13, which is CLOSED and titled "superseded by #2739"; it never merged)

⚠️ **Re-scoped by [decisions.md 21](decisions.md#21-ss-3-where-key-material-lives-and-what-the-substrate-stops-storing-2026-08-03), which shrank this rather than growing it.** Three of the
deliverables below turned out to be already done, unnecessary, or built on a false premise:

- **"a single `apkamPublicKey`"** was already true — `EnrollDataStoreValue` declares
  `late String apkamPublicKey`, not a list.
- **The durable `SecretStorePersistence` backend is not built, on purpose.** Key material that must
  survive a restart is filed into `AtKeys` instead (ruling 1), which keeps this atSign's private keys
  out of whatever backend an app supplies and puts them under `AtKeysIo`'s never-lose contract. The
  SDK ships no implementation of the seam.
- **"a restart loses the CK cache" was wrong.** Content keys are a genuine cache: the read path
  re-fetches the conveyance record and re-opens it, so a restart costs a round trip, not data. What
  a restart *did* cost was a fresh CK and a permanent conveyance record per destination — fixed by
  recording the current `ckKid` (ruling 2), never the key.

**Landed:** the `mldsa65` branch and record-authoritative APKAM verify (legacy PKAM keeps the wire
value — the functional suite authenticates over that path with an `ecc_secp256r1` key, so pinning it
would have broken working behaviour); serialised `SecretStore` saves; jitter plus
suppress-on-observed for the pull thundering herd; the current-`ckKid` pointer; and
`NskeyPrivateFiling`, which moves an arriving nskey private out of the transit buffer into `AtKeys`.

**Owed:** parity across every atServer implementation before a PQ client can rely on the verify
change — at least one rejects `signingAlgo:mldsa65` while *parsing*, so a PQ client meets an
invalid-syntax error rather than an auth failure, and it carries no ML-DSA support to add a branch
to. And `NskeyPrivateFiling` has no producer until **SS-4** conveys a private, so the `Secret` name
it consumes (`__nskey.<nskeyKid>`, in the key's namespace) is a contract SS-4 must write to.

**Goal:** durable secret storage + smoothed anti-storm + the single-key record-authoritative verify.
**Builds on:** SS-2 ◀ P-2 (satisfied — at_chops 3.4.0 published 2026-07-17).
**Deliverables → [design.md](../design.md)** (SecretStore durability + single-key verify): the enrollment record keeps a **single** `apkamPublicKey`; PKAM verify selects RSA vs
ML-DSA from the record's **`signingAlgo`** (**record-authoritative** — `_validateSignature` reads the
*stored* algo, **not** the client-supplied `verbParams[atPkamSigningAlgo]`; legacy null → `rsa2048`). Plus
the genuine hardening: wire `SecretStorePersistence` to an on-disk per-enrollment backend (preserve monotonic
`putIfNewer` ordering) + jitter/backoff on the anti-storm rate cap.
**Acceptance → [acceptance.md](../acceptance.md):** store survives close/reopen with version ordering; an
rsa2048-stamped key verifies via RSA, an mldsa65-stamped key via ML-DSA only (no fallthrough), legacy null →
rsa2048; both functional + e2e.
**Effort:** L.
**Watch-outs:** the `signingAlgo` field on `EnrollDataStoreValue` is owned by SS-1b; the pkam grammar literal
by SS-1a.
**coversD1:** D1-F DEP3 (single-key + signingAlgo).

### SS-4 — nskey minting + signing-root lifecycle + correspondence check · at_client · L — [#2087](https://github.com/atsign-foundation/at_client_sdk/issues/2087) — **LANDED, less key-transparency publication (scoped out by ruling 24.4)**

⚠️ **Re-scoped by [decisions.md 22](decisions.md#22-ss-4-when-a-namespace-key-is-minted-and-what-must-be-true-first-2026-08-03).** Read that first; the deliverables below
predate it and describe `pqpublickey` as a KEM, which [decisions.md 18](decisions.md#18-pqpublickey-becomes-the-user-owned-signing-root-2026-08-03) already replaced.

**Landed.** Minting under a remote-first immutable `_nskeylock`, with the private made durable in
`AtKeys` **before** the public half is published — and a mint that cannot store its private
publishing nothing at all. Seeding at client init across the namespaces a client is authorised for,
behind `AtClientPreference.seedNamespaceKeys` (default **off**), with legacy clients seeding
`preference.namespace` and `*` enrollments seeding nothing. Conveyance of every held generation,
read from `AtKeys` rather than the in-memory secret store. The public/private correspondence check
on an arriving private — exact, because an X-Wing secret key is its seed. And
`PqSigningRoot.mintIfAbsent`, immutable create-once, privileged enrollments only.

**Owed — the chain's plumbing, which is the larger half:**

- ~~the parent signing a child's APKAM public key at approval and **conveying** the signature
  (ruling 7), and the child publishing it onto its own `_apsk`'s `appMetadata` on first run~~
  — **done**, both halves, and covered live: `PqSigningChain` signs at approval and conveys
  over the substrate, `publishPendingLink` stamps it at client start behind three refusals,
  and `enrollment_chain_link_live_test` watches a link survive a real `_apsk` round trip;
- ~~chain **verification** — walk `_apsk` to `_apsk` up to the root~~ — **ruled and built**
  ([decisions.md 24](decisions.md#24-how-the-approval-chain-terminates-at-the-root-2026-08-04)).
  `PqSigningChain.verifyChain` returns a `ChainResult` — `anchored` / `chained` / `unsigned` /
  `broken`. The fourth is an addition to ruling 3's three and deliberate: an absent link means
  nobody has vouched yet, a *bad* one means something claimed to and the claim fails, and folding
  the second into the first would report an attack as a rollout artefact. Every hop checks the
  signature, that the link vouches for the enrollment it is attached to, and that it covers that
  enrollment's published key — a signature alone proves only that the parent said *something*.
  Cycles and over-long chains end as `broken` rather than being treated as impossible;
- ~~a losing enrollment **pulling** the root private from a privileged holder~~ — **superseded by
  push, not built as a pull.** A fully privileged enrollment is *conveyed* the private when it is
  approved, and anchors itself from it. A pull would still be the answer for a privileged
  enrollment that predates its holder's ability to send, which no current flow produces;
- **key-transparency publication mechanics** — when a root is submitted, and what a client does if
  the log is unreachable at mint. Still un-grilled, and [decisions.md 24](decisions.md#244-built-since-and-what-is-still-owed)
  scopes it out deliberately: it concerns what the root *is*, not how a chain terminates at it.

**Explicitly out of scope:** changing APKAM keypairs from RSA to ML-DSA. The chain is built over
today's RSA keys and the algorithm swaps later without the chain changing, because the root signs an
enrollment's public key whatever algorithm it is. `_apsk` migration needs thinking through first.

**Goal:** mint the per-namespace key material and the atSign-level root PQ key — the first convergence
feeder into the data path.
**Builds on:** SS-3 + **P-3** (pqpublickey name/cold-start target) + **S-3** (updatable local key
storage for nskey privates).
**Deliverables → [design.md](../design.md)** (nskey minting + pqpublickey lifecycle): mint **one** nskey
keypair per `(atSign, namespace)` and publish its public half **eagerly at mint** to
`public:__nskey.<ns>@alice`, taking the short-ttl immutable `_nskeylock.<ns>@alice` first so two of the
owner's enrollments cannot race; the record is **mutable** so B-2 can overwrite it on rotation. Both the
`nskey` public half and
`public:pqpublickey@alice` are **advertised as APKAM-signed envelopes** (design.md [section 2.1](../design.md#21-kpid-addressing-__ssenv-envelope-signverify) *Advertised-key
authenticity*), so a fetching client verifies them against the publishing enrollment's `_apsk` — same path
same-atSign and cross-atSign. `pqpublickey` create/seed/serve/pull under
`pqid:<kid>` + root no-namespace serve exception; public/private correspondence check in `_consume` (the
signature is primary; correspondence is the secondary check). The
nskey private is conveyed per-APKAM as a Secret over the substrate.
**Acceptance → [acceptance.md](../acceptance.md):** UC-A3.2 (2nd APKAM obtains the nskey private, decapsulates
a test secret sealed to it; app_2 refused to an app_1-only client); a fetched `nskey` / `pqpublickey`
advertisement verifies against the publisher's `_apsk` and a tampered one is rejected; **an unauthenticated
scan of the atSign returns no `public:__nskey.…` key, with or without `showhidden`** — a guaranteed protocol
property, covered as a regression guard; UC-B5.1/B5.3 (offline pull; `pqpublickey` create-once race,
and the `_nskeylock` mint race); pqpublickey create→seed→serve→pull + correspondence-mismatch rejection.
**Effort:** L–XL.
**Watch-outs:** delivers **key material only** — the value-level providers are B-1. The **first convergence
feeder** into the data path.
**coversD1:** nskey/pqpublickey material slice of D1-B B1 + D1-F F2.

---

## 6. Phase B — the nskey data path (B-1, the D1 centrepiece)

### B-1 — at/nskey + at/symmetric/AES/GCM providers + cold-start · at_client · XL *(title's former "capability marker, negotiation" scope removed by [decisions 36](decisions.md#36-the-rollout-is-the-apps-decision-capability-markers-built-examined-and-removed-2026-08-05))*
**Goal:** the value-level data path — the **D1 GA convergence point**.
**Builds on:** #1930 (seam) + P-1 (`pqSeal`) + S-2 (`CryptoContext.keys`) + **SS-4** (nskey key material) + P-3. *The substrate delivers the privates; this delivers the providers.*
⚠️ **The SS-4 prerequisite holds for `B-1c` onward** — `B-1a` needs no nskey material at all, and `B-1b`
proceeds against a test fixture that supplies the nskey private directly (see the chunk table below). B-1
**as a whole still requires SS-4**; the dependency is not dropped, only deferred past the first two chunks.
**Deliverables (plan-altitude headings; full mechanics → [design.md](../design.md), D1 nskey data path):**
- **Layer 3 — `at/symmetric/AES/GCM`:** AES-256-GCM under a symmetric CK cited by `ckKid`;
  `appMetadata{providerId, ckKid, iv, ns, ckNs}`; binary-safe; CK cache keyed
  `(owner, ckNs, ckKid)`. `ns` is the value's own namespace and is what the AAD binds; `ckNs` is where
  the CK lives ([decisions.md 19](decisions.md#19-nested-namespaces-the-nskey-is-resolved-by-walking-up-2026-08-03)).
- **Layer 2 — `at/nskey/XWING/AES/GCM`:** `pqSeal` the CK to the recipient's nskey public half, written once as
  `<ckKid>.__ck.<ckNs>@<owner>`; `appMetadata{providerId, recipientKind, ckKid, nskeyKid, ns}`.
  Self data seals to the owner's own nskey; sharing seals to the recipient's nskey (fetched via
  `plookup` on `public:__nskey.<ns>@<recipient>`) — one keypair, same provider, uniform self/cross flow.
  `nskeyKid` names the generation, so a reader holding several after a rotation indexes straight to it.
- **Namespace resolution:** a sender walks the value's namespace most-specific-first and seals to the first
  published nskey; that namespace is `ckNs`, and an exhausted walk is cold start. Senders remember the
  levels they have found **empty**, so a composed sub-collection namespace pays its probes once rather
  than per write; remembering *hits* instead is unsafe and rejected, since it skips the deeper probes.
  Required for AtCollection, whose sub-collection namespaces embed a per-**item** id.
- **Get/put routing + the CK manager:** `CkManager.ensureCurrent(dest, ns)` re-`plookup`s the
  destination's advertised nskey and mints + conveys a CK when there is none for that destination or the
  advertised `nskeyKid` has moved. CKs are **per recipient**, so a cross-atSign write runs it twice
  (recipient scope, then the sender's own). The re-`plookup` is the **only** way a sender learns of a
  rotation — there is no failure path back to it — so without it B6 revocation does not hold for inbound
  data. Out-of-order sync: decapsulate `<ckKid>.__ck` on demand with the reader's **own** nskey private,
  else a typed deferred state, not a hard failure.
  ⚠️ **It cannot live inside `encrypt`.** Minting a CK means *writing the conveyance record*, and
  `encrypt` is called from inside `PutRequestTransformer.transform` — issuing a `put` from there
  re-enters the pipeline on a half-built verb builder. It runs as a preparation step in `_putInternal`
  instead, reached through a **`PreparesWrites`** interface kept separate from `CryptoProvider` (adding a
  member to that would break every external `implements CryptoProvider`, the shipped example included).
  Recursion terminates because the conveyance is routed explicitly to `at/nskey`, which does not
  implement `PreparesWrites` — pinned by a test, not left as an argument.
- **B3 capability marker:** *(REMOVED by
  [decisions 36](decisions.md#36-the-rollout-is-the-apps-decision-capability-markers-built-examined-and-removed-2026-08-05)
  — no marker, no per-destination selection; the app's build decides what it
  writes.)* What survives of this bullet: `providerId` on stored values **and**
  notification frames, and section 16's provider-id ruling itself.
- **B4 cold-start:** when the recipient has never used the namespace, so there is no
  `public:__nskey.<ns>@<recipient>`, the write **fails** — the atSign-level key is a signing root and
  cannot receive an encapsulation, so there is no PQ target to fall back to. The refusal names the
  recipient and the namespace, and a pre-flight query answers the same question first; legacy is
  reachable only by explicit opt-in. The recipient's first *use* of the namespace mints and publishes
  its nskey (via SS-4), and the sender's next `ensureCurrent` re-`plookup` picks it up.
  (Seal-and-hold was considered for R-1 and **deferred, not built** — no consumer
  asked for more than the named refusal + explicit fallback;
  [decisions 36](decisions.md#36-the-rollout-is-the-apps-decision-capability-markers-built-examined-and-removed-2026-08-05).)

**Spike state (branch `gkc-pq-d1-spike`, 2026-08-04).** The data path is built, and
**both the self-data and the cross-atSign directions work end to end against a live
atServer**. Advertised nskeys and key packages are signed and verified, cold start fails
cleanly with a pre-flight query and an opt-in legacy escape hatch, and nested namespaces
resolve by walking up with `appMetadata.ns` / `ckNs` on the wire — covered multi-segment in
both live suites, which previously used single-segment namespaces only.
`packages/at_client` green at
**919 passing / 7 skipped**, `tests/at_functional_test` at **131**,
`tests/at_end2end_test` at **50** with no skips (all re-run together
2026-08-05, after the to-define ratifications, RF-2b, RF-2c's switch-over and
RF-2c's UC-B1.x/B2.x rows landed). Also green: `at_auth` 160,
at_secondary_server **867** (the RF-SRV spike branch, resolving the workspace
at_chops 3.4.2 via `pubspec_overrides.yaml`), `at_chops` 219,
`at_commons` 505. The acceptance burn-down reads **33 of 40**.

*Proven live (functional suite, `tests/at_functional_test`):* self put/get round-trip
through the whole pipeline including the pre-pass, the conveyance record and key
validation; content-key reuse across writes; byte-exact binary; the `public:__` scan
property that eager publication depends on; and — after a sync — an authenticated
`llookup:all:` against the atServer confirming the stored record still carries its
`appMetadata` routing and cites its content key. That last probe is the one that
separates *stored on the server* from *reconstructed by the client*: `put`/`get` are
local-first, so a suite built only from them passes with nothing ever leaving the
device, which is exactly how the `appMetadata` drop below went unseen.

*Proven live (e2e suite, `tests/at_end2end_test`):* alice shares with bob and bob opens
it with **his own** nskey private — the assertion the record-owner/nskey-owner split
turns on, and the one self data cannot exercise because there the two atSigns coincide.
Also that a sender cannot decapsulate a CK she sealed to her recipient, and that a
self-copy takes a different CK. **And, since 2026-08-04, the notification *receive* path:**
`ConcurrentClients` holds both atSigns live at once (one `AtClientManager` each), so a monitor
on bob receives what alice sends and **decrypts** it — proving `providerId` travels on the
notification frame and routes the decryption. That closed UC-A3.4 / UC-A4.4, and finding it
required fixing a real defect first: the content-key conveyance was losing a race to its own
announcement ([decisions.md 26](decisions.md#26-uc-a44-a-conveyance-that-loses-the-race-to-its-own-announcement-2026-08-04)).

*Was blocked; cause found and fixed in this package.* Cross-atSign reads failed because
the **sync push** dropped `appMetadata`: `SyncServiceImpl._metadataToString`, a
hand-rolled duplicate of `Metadata.toAtProtocolFragment`, never emitted the field, so the
record reached the atServer without it and `CryptoRuntime` fell back to `legacy`
([decisions.md](decisions.md) section 17). This affected **every** provider's synced
writes, including those shipped in `at_client` 3.14 — not PQ-specific. It was first
recorded here as an atServer gap; that attribution was wrong, and section 17 records the
probe that distinguishes *not returned* from *never stored*. The duplicate serializer is
deleted, `nskey_cross_atsign_test.dart` is un-skipped and green, and a
`VerbSyntax.update` regex-match guard now fails if a field is ever emitted out of order.

*Adversarial review of the branch (2026-08-02), and what it changed.* Six independent
lenses over the eight commits, each finding put to two refuters, then a completeness
critic. Seven findings survived; five were defects introduced here and are fixed on the
branch: a CK promoted to *current* before its conveyance was durable (a failed write
poisoned the destination permanently); the notify path selecting a crypto provider before
the namespace was resolved, silently downgrading to legacy while `put` on the same key
used nskey; a conveyance written local-first for a remote-only value; a bare `catch`
reporting a tampered envelope as "not yet synced"; and `CryptoConfig.nskey`'s required
`NskeyKeyRing` not being exported from the barrel. The critic also found that the notify
*read* path built its `AtKey` without a namespace — so fixing the send half alone would
have turned a silent downgrade into a hard receiver failure — and that four more
hand-rolled metadata converters survived the one this branch deleted; all are swept, with
`metadata_converter_sweep_test.dart` pinning the `Metadata` field inventory so a new field
cannot be dropped by any of them unnoticed. Every defect but one came from code the unit
suite covered and passed.

The highest-severity *contested* finding was also acted on: the data layer called AES-GCM
with an empty AAD, so a ciphertext was bound to its content key but not to its record —
and a CK covers every record in its `(owner, namespace)` scope, so a valid ciphertext
could be relocated between records by anyone able to write the store and would still
authenticate. `at/symmetric/AES/GCM` now authenticates
`providerId:sharedBy:sharedWith:<key>.<namespace>` as AAD, which is the layer-3 equivalent of
the HPKE `info` binding the conveyance already had. It is a value wire-format change,
taken now because nothing written under the old form exists outside the spike.

*Owed, in rough dependency order:*

| Owed | Where it belongs |
|---|---|
| ~~Cold-start fails by design, with an exception, a fallback and a query~~ — **done on the spike branch.** `NamespaceKeyUnavailableException` carries the atSign and namespace and is raised by the *pre-pass*, so nothing is in flight when it fires; `CryptoRuntime.isReadyFor` answers the same question in advance via the `ReportsReadiness` seam; `AtClientPreference.allowLegacyCryptoFallback` (default false) reroutes the write to legacy, per write, so the fallback is forward-only. Covered live in `nskey_data_path_live_test`'s cold-start group ([decisions.md 18](decisions.md#18-pqpublickey-becomes-the-user-owned-signing-root-2026-08-03)) | **B-1c** |
| ~~Advertised-key signature verification~~ — **done on the spike branch, both halves.** `PublishedNskeyKeyRing` signs its own nskey advertisement and `ApkamSignedAdvertisedKeys` verifies a peer's; `KeyPackageRegistration.signedKeyPackagePayload` signs the key package and `VerbEnrollmentDirectory` verifies it against the advertising enrollment's `_apsk`, rejecting unsigned, tampered, wrong-signer and forged-claim packages. No unverified advertised-key path is left. **Owed:** the key-package half has no live coverage — `enroll:listns` is unit-only until SS-2 wires the production path | **SS-1c** / **SS-2** |
| **Client start got two new side effects with `collectConveyedKeyMaterial`, both deliberate and neither yet measured.** Every client carrying an `AtKeysIo` now (a) calls `KeyPackageRegistration.register()` at start, which **publishes `_apsk`** — redundant for an enrollment, since the atServer publishes it on approval, but the only route for a legacy PKAM client whose peers must verify its envelopes; and (b) does one **remote sweep**. That is one extra write and one extra scan per client start, on an unawaited path. The sweep also **consumes and deletes** the envelopes it finds, so an app subscribing to `receivedSecrets` *after* constructing its client sees no arrival event for anything waiting at start — the secret is in the store, which is where `waitForSecret` looks first, so the pull flow is unaffected but a listener-only app is not. Owed: decide whether the `_apsk` publish should be skipped when the client has an enrollment id, and measure the start-up cost | `at_client` |
| ~~The acceptance burn-down misreports progress~~ — **repaired 2026-08-04.** Both audited causes are fixed and the figures are now verified rather than estimated. (a) A row proven in another package can be claimed: `provenIn` cites the live test and asserts it is still there — it does not re-run the proof, since this suite runs in `at_client`'s unit tests and cannot reach the functional or e2e packages, but a renamed or deleted live test now turns the citing row red instead of letting its evidence vanish. (b) `blockers.dart` no longer names landed projects: SS-2, SS-4 and B-1's **21** rows were re-labelled from `blocked: <project>` to `owed: scenario not yet written`, because a project landing makes its scenarios *owed a test*, not *proven* — conflating those is what made the number misleading in both directions. Four had a live proof and now cite it (A2.1, A3.3, A4.1, A4.4), so the suite read **5 of 40** scenario rows green, up from **1**, with **17** genuinely owed a test. The old "4 of 43" was itself wrong optimistically: it counted `catalogue_test.dart`'s three guards as scenarios. The guard that tracked B-1's share now tracks the owed count, since a guard pinned to a finished project silently stops guarding. **All 17 were discharged the same day**, taking the suite to **22 of 40** green and **0** owed. Fifteen were written or cited; UC-A3.2 turned out to be a catalogue error rather than a missing test, and UC-B5.1 needed production code that did not exist. Every remaining skip names a project that has not landed (R-1, B-2, RF-SRV, RF-2b, ON-1), so `blockers.dart` is now purely a project ledger. The rows written were: four cross-cutting invariants, UC-A3.4, UC-B5.2, then — once a functional test for the immutable signing-root create existed — the create-once invariant and UC-B5.3's race, and finally UC-A3.2 once its catalogue text was corrected. Then UC-A2.2 and UC-A2.3. Four new live files: `pq_signing_root_create_once_test.dart`, `nskey_seeding_live_test.dart`, `enrollment_namespace_gate_test.dart`, `copied_keyfile_test.dart`. Functional suite **120 green**. UC-A2.3 is proven at two layers deliberately — the row insists the namespace boundary is enforced *at the atServer*, "not by a client-side refusal alone", and a filter in the sender is worth nothing against an enrollment that simply asks for the record; the atServer refuses the scoped enrollment's `llookup` naming the enrollment and the key, while the approver reads the same record, so the refusal is a gate rather than an absent record. UC-B5.1 was then picked up and turned out to be **blocked rather than owed**: `requestSecret` has zero call sites in `lib/`, so nothing ever asks for the signing root, and `PqSigningRoot.mintIfAbsent` says so in its own dartdoc. The substrate's request/answer round trip is complete, on by default and unit-covered — the missing piece is an *initiator*, which is wiring rather than design, and it matters because the root carries no namespace and is therefore excluded from the `enroll:listns` fan-out by construction, leaving the pull as its only route ([decisions 30](decisions.md#30-uc-b51s-pull-backstop-has-no-initiator-2026-08-04)). What remains **owed** is **5**: the no-RSA unit row (which enumerates the auth path, so it waits on the ML-DSA row), ML-DSA record-authoritative auth, the atServer half of advertised-key verification, and the two e2e rows UC-A4.2/UC-A4.3. Two of the six needed no new test: the published nskey's fetchable-not-enumerable property was already proven with controls by `underscore_public_key_hiding_test`, and citing it beat duplicating it. One needed a doc first — the B-1 bench harness had been run when it was built but its numbers were never recorded, so "performance is measured, not assumed" was asking for a budget that existed nowhere a reader could find it ([decisions 28](decisions.md#28-the-pq-performance-budget-measured-2026-08-04)). And one, UC-A3.2, turned out to be a **catalogue error rather than a missing test**: it triggered minting on the first put, which was never built and contradicted UC-A3.3's proven "a keyless write fails". Ruled that the code is right — a put that minted would hide a lock, a keygen, a publish and a per-enrollment conveyance behind one write, on a user action's latency path — and `acceptance.md` 4.2 was amended ([decisions 29](decisions.md#29-uc-a32-describes-a-mint-trigger-that-was-never-built-2026-08-04)). Seeding had unit coverage only, and an `unawaited` call behind a default-false flag is the exact shape that passes every unit assertion while never executing |
| ~~UC-A2.1 is not met, though SS-2 reads complete~~ — **built 2026-08-04**, [decisions.md 23](decisions.md#23-uc-a21-reversing-the-enrollment-key-exchange-2026-08-04). `EnrollmentKeyExchangeMode.pq` stops the enrollee generating and RSA-wrapping `apkamSymmetricKey`; the approver mints it and seals it to the advertised key package over the substrate, and `enrollmentApkamSymmetricKeyResolver` collects it after PKAM. Nothing RSA-wrapped rides the request. Covered live in `enrollment_pq_key_exchange_live_test.dart`, including the enrollee recovering the key over its own namespace-scoped PKAM connection. **Owed:** the test cannot pass against `vip` until the atServer relaxation is promoted | **SS-2** residual |
| **A notification whose transform throws is never re-delivered — a data-loss path, not a log-level one.** The `__ck` race that produced it is fixed (conveyance now goes remote-first) and the drop is now logged at `warning` rather than `finer`, so it is visible. But nothing retries the notification itself: if a transform fails for any reason — a key that has not arrived, a provider not yet registered — that notification is gone, and no later event re-delivers it once the missing piece lands. Recorded at [decisions.md 26.3](decisions.md#26-uc-a44-a-conveyance-that-loses-the-race-to-its-own-announcement-2026-08-04); previously captured only inside the struck-through `B-1e` row, where it would have been lost when that row was read as resolved. Needs a decision on where redelivery belongs (the monitor's own queue, or a client-side hold-and-retry) before it needs code | **unowned** |
| ~~BOTH test packs' rails are pointed away from CI's image and must be reverted before any PR~~ — **resolved 2026-08-10.** Both composes commit `image: ${VIRTUALENV_IMAGE:-atsigncompany/virtualenv:vip}`, so CI and a clean checkout resolve the published image with no environment set, and each `runLocal.sh` opts a local run into `at_virtual_env:local` and skips `docker compose pull` for a name no registry serves. Nothing is pointed away from CI's image and there is nothing to revert. What survives is the underlying fact, not the rails problem: the published `vip` does not store `EnrollParams.metadata`, so the key-package path cannot be exercised against it until a canary→prod promotion. |
| **A PQ-capable client cannot tell a legacy atServer from an old peer.** Against an atServer that drops `EnrollParams.metadata`, the key package vanishes silently and the approver reads absence — which [decisions.md 20](decisions.md#20-ss-2-how-the-key-package-reaches-an-enrollment-and-how-conveyance-fires-2026-08-03) ruling 2 treats as *ordinary*, because it also means "an older client". So conveyance no-ops fleet-wide with nothing saying why. UC-B0.1 requires aborting cleanly and logging the reason; `info` returns only a version string, with no feature list to check | **RF-SRV** / UC-B0.1 |
| **Parity across every atServer implementation for the `mldsa65` verify branch.** At least one rejects `signingAlgo:mldsa65` while *parsing* the command, so a PQ client meets an invalid-syntax error rather than an authentication failure. It already stores `signingAlgo` but never reads it, and carries no ML-DSA support — a dependency decision, not an edit | **SS-3** |
| **D1 GA critical path, re-derived 2026-08-05 after the three-scenario re-examination** ([decisions 36](decisions.md#36-the-rollout-is-the-apps-decision-capability-markers-built-examined-and-removed-2026-08-05)–[41](decisions.md#41-the-to-define-list-2026-08-05)). **R-1 is DELIVERED, shrunk to D1-D**: `disallowLegacyEncryption` landed 2026-08-05; the marker/negotiation half was built, proven at three layers, and removed the same day; C3 deferred unbuilt. **Newly ON the GA path:** **SH-1** (M, key-material self-heal — the conveyance hole meant an enrollment created after a mint was stranded; in progress 2026-08-05) and **RF-SRV** (L, server self-enroll — every scenario's "upgrade the enrollment", was mis-filed off-path). **Re-timed:** ON-1 mints/publishes legacy material by default (decisions 37); R-2 keeps the flag flip but loses phase-4 stop-existing to a later ecosystem-gated release; B-3 phase 3's client-side stop likewise. Remaining on the GA path: **SH-1**, **RF-SRV**, **B-2** (L), **ON-1** (M), **R-2** (M), **S-3** (L). The to-define list ([decisions 41](decisions.md#41-the-to-define-list-2026-08-05)) is the authoritative open-questions ledger — 12 items with owners; **all 12 ruled 2026-08-05** ([decisions 42](decisions.md#42-the-to-define-list-ruled-2026-08-05)), so the definitions now land in their owner projects as implementation | plan |
| **D1 GA critical path, re-derived 2026-08-04 against pub.dev and the skip counts.** Complete: P-*, S-1/S-2, SS-1a/1b/1c, **SS-2**, **SS-3**, **SS-4** (bar key transparency, parked), **B-1** incl. all chunks. Remaining on the GA path: **R-1** (L, migration machinery + `disallowLegacyEncryption` + strict mode), **B-2** (L, nskey rotation + revocation), **ON-1** (M, PQ-native greenfield onboarding), **R-2** (M, the 4.0.0 flag flip), and **S-3** (L, updatable `.atKeys`/keychain). Off the GA path: the **RF-\*** retrofit trio. Referenced only: D2-1. Separate track: IS-1. Publish gates verified against pub.dev the same day — at_client 3.14.1/3.14.0, at_commons 5.14.0/5.13.0, at_chops 3.4.2/3.4.1, at_auth 3.4.0/3.3.0 (so the old at_auth `3.3.0-rc1`→stable gate is **closed**). ⚠️ **Re-verified 2026-08-11, and two of these moved:** in-tree/published is now at_chops **3.6.0**/3.5.0 and at_commons **5.15.0**/5.14.0. ⚠️ **Re-verified again 2026-08-22, and the figures above are a 2026-08-04 SNAPSHOT — do not read any of them as current.** Published now: at_commons 5.16.0, at_chops 3.6.0, at_lookup 3.6.1, at_server_status 1.1.1, at_auth 3.3.0, at_client 3.14.0. In-tree now: at_lookup 3.7.0-rc1, at_server_status 1.1.2-rc1, at_auth **4.0.0-rc1**, at_client 3.15.0-rc1. The `at_auth 3.4.0` above is the version this heading carried until `96025e46c` renamed it for the major; **no at_auth 3.4.0 was ever published or ever will be** | plan |
| **`at_auth` 3.4.0 is open and unpublished**, and at_client now depends on `AtEnrollmentRequest.metadataBuilder`. Same masking as the at_commons row below: workspace resolution hides it, so a green build says nothing | `at_auth` |
| ~~`at_end2end_test` has not been run since at_auth's surface changed~~ — **run 2026-08-04, green at 41 with no skips**, the same count as 2026-08-03. So neither at_auth's added surface (`EnrollmentKeyExchangeMode`, `apkamSymmetricKeyResolver`, `approvedWithMintedKey`, the grown `AtEnrollmentResponse`/`EnrollmentRequestDecision`) nor the arrival-path work regressed it — the latter mattering because that commit added work to `AtClientImpl`'s init, which every e2e test drives. All four rails now verified together: `at_client` 825/39 skipped, functional 113, e2e 43, `at_client_flutter` analyze clean | `at_end2end_test` |
| ~~`NskeyPrivateFiling.start` is an arrival hook nothing calls~~ — **fixed 2026-08-04, and it was three defects rather than one.** The prescription recorded here — give the nskey path `PqSigningRoot.filePendingPrivate`'s store-check treatment — would have produced a second method that looks right and files nothing, because the model it was told to copy had the same defect one layer down. `SecretStore` is an in-memory map whose only populator is `PairwiseSecretSharing.sweepOnce`, and **no production code in `at_client` ever called `sweepOnce` or `startListening`** — so at client start that store is empty and the root private was never filed either. One layer lower again: `KeyPackageRegistration.register()` mints a fresh X-Wing keypair per process (`loadApkamKeys` was wired only in tests), so the running client's `kpid` was never the one its enrollment advertised and a sweep would have scanned an address nobody writes to. `collectConveyedKeyMaterial` closes all three in order — bind the key package to `AtKeys`, sweep remote, then file — and `NskeyPrivateFiling.filePending` replaces `start`/`stop`. Live-covered in `conveyed_key_collection_test.dart`, with both defects reinstated as negative controls: disabling the binding fails the kpid assertion, disabling the sweep fails both tests | `at_client` |
| ~~**The substrate's unit fixture cannot see routing** — one map backs local storage and the atServer, so a local-first write and a remote-first one are indistinguishable by results. Routing is asserted directly instead (`putOptions`, `scanRoutedRemote`). Closing it properly means modelling sync in the fixture~~ — ✅ **CLOSED 2026-08-16.** `buildRemoteBackedMockClient` takes an optional `localData`; supply it and the two stores diverge exactly as a device's do — a local-first write lands only locally until `syncToRemote`, and a local-first read of a key only the atServer holds **misses**. Divergence is opt-in because the nine callers that predate it assert routing directly and specify the default. Proven by mutation in `remote_backed_client_routing_test.dart`: making local reads fall through to remote turns the peer-write row red | `at_client` tests |
| **`at_client` cannot publish until every floor it declares is on pub.dev.** ✅ **The at_commons/at_chops half CLOSED 2026-08-21**, when gkc published at_commons 5.16.0 and at_chops 3.6.0 — at_client's `^5.15.0` and `^3.6.0` are both satisfied. What still gates at_client is `at_lookup: ^3.7.0-rc1` and `at_auth: ^4.0.0-rc1`, against pub.dev's 3.6.1 and 3.3.0. ⚠️ **This cell named `^3.7.0` and `^3.4.0` until 2026-08-22** — neither was what at_client's pubspec said: at_lookup carried the `-rc1` suffix from [14.49.2](implementation-plan.md#14492-every-remaining-package-publishes-as-a-release-candidate), and at_auth had gone major. Read the pubspec, never this sentence: `grep -E '^  at_(lookup|auth|chops|commons):' packages/at_client/pubspec.yaml`. ⚠️ **And a floor being satisfiable is not the same as it being right:** at_client's `at_commons: ^5.15.0` is satisfied by pub.dev and still **too low**, because `notify_request_transformer.dart:154` calls `metadata.copy()`, which first exists in **5.16.0**. The same defect was found and fixed in at_auth during its carve. ⚠️ **Restated 2026-08-11:** the floors this row used to name — `^5.14.0` and `^3.5.0` — became *published* numbers holding *other* content, because trunk released both while the spike claimed them. Checking pub.dev for 5.14.0/3.5.0 and finding them live is the trap this row now exists to prevent. Workspace resolution masks the gap exactly as the publish-ordering caution warns, so a green build says nothing | `at_commons` / `at_chops` |
| ~~The secret-sharing substrate has no live coverage in either pack~~ — **opened, not closed.** `secret_sharing_delivery_test.dart` now drives it live: the envelope is on the atServer by the time `sendEnvelope` returns, and a client that has never synced fetches and decrypts it from there. Both fail against the pre-fix build and nothing else does, so they detect the defect rather than merely passing. ~~**Still owed:** everything beyond envelope delivery — `pushSecretToNamespaceMembers`, the `requestSecret`/`waitForSecret` pull flow, and anything needing two real enrollments, which waits on SS-2~~ — ✅ **closed 2026-08-18, and the SS-2 clause was never right.** The pull flow runs live in `nskey_park_and_redrive_live_test.dart` and `signing_root_pull_two_enrollments_test.dart`, and **eight** functional files drive two real enrollments (`apsk_server_side_test`, `enroll_update_live_test`, `nskey_park_and_redrive_live_test`, `nskey_rotation_live_test`, `nskey_self_heal_live_test`, `nskey_self_notify_live_test`, `pkam_record_authoritative_test`, `signing_root_pull_two_enrollments_test`). Two enrollments of one atSign need APKAM, not `__ssenv`; SS-2 gates the atServer's update-put auto-notify and nothing here | `at_functional_test` |
| ~~**The substrate's unit fixture backs local storage and the atServer with one map**, so it cannot see a local-first-vs-remote-first defect on the read side at all — which is how the `__ssenv` wake-up ordering bug survived. Fixed for the write side by asserting the put's routing directly and for the sweep by asserting the scan's, but the blind spot itself remains: any future substrate read that depends on routing is untested unless someone remembers to assert the routing rather than the result. Closing it properly means modelling sync in the fixture, so local and remote diverge and a wrong route fails on its results. The live pack now covers the two paths that matter today~~ — ✅ **CLOSED 2026-08-16.** `buildRemoteBackedMockClient` takes an optional `localData`; supply it and the two stores diverge exactly as a device's do — a local-first write lands only locally until `syncToRemote`, and a local-first read of a key only the atServer holds **misses**. Divergence is opt-in because the nine callers that predate it assert routing directly and specify the default. Proven by mutation in `remote_backed_client_routing_test.dart`: making local reads fall through to remote turns the peer-write row red | `at_client` tests |
| ~~Real nskey minting + per-APKAM conveyance~~ — **done.** `mintAndPublish` takes a remote-first immutable `_nskeylock`, files the private into `AtKeys` **before** publishing, and publishes nothing at all if it cannot. `NskeySeeding` mints at client init across a client's authorised namespaces and conveys every held generation, reading from `AtKeys` rather than the in-memory store. `InMemoryNskeyKeyRing` remains for tests only | **SS-4** |
| ~~**Mint** of `public:pq_signing_root@<atSign>`~~ — **done, and so is its conveyance.** `PqSigningRoot` mints immutable create-once with the private filed before publish; the private is conveyed to fully privileged enrollments at approval under a per-enrollment name, filed into `AtKeys` at start, and `PqSigningChain.publishOwnRootLink` anchors the holder to it at mint and at every start. Live-covered end to end, including that the atServer really does grant `*` + `__manage` — without which the privilege gate would have been tested against two identical cases | **SS-4** |
| ~~Wire the nskey `CryptoConfig` at init~~ — **done 2026-08-04** ([decisions.md 27](decisions.md#27-the-era-default-read-the-new-scheme-everywhere-write-it-once-2026-08-04)). Not by adopting `CryptoConfig.nskey`, which sets the AES-GCM path as the *write* default and is therefore the 4.x shape: final 3.x reads PQ and still writes legacy, so `CryptoConfig.readsNskeyWritesLegacy` registers the same provider set with `defaultProviderId` left at `legacy`. `forClient` stopped being a constant — the providers hold per-atSign state, so the set is built once per client at init and looked up, via an `Expando` rather than written into the shared preference object. The era ring gets the client's `AtKeys` as its `privateFiling`, without which it would see only what this process minted. Live-covered end to end by `era_default_read_test.dart`: **bob, given no `CryptoConfig` at all**, opens a record alice sealed to his namespace key, with alice opting in to `CryptoConfig.nskey` to write PQ — the asymmetry as an executable statement. (An owed item claiming the era ring was unreachable from a test was recorded and then withdrawn the same day: `NskeyProvider.keyRing` is public and exported, so it always was.) | **SS-4** |
| ~~`AtClientPreference.crypto` signals "app named nothing"~~ — **done; reshaped 2026-08-09** ([decisions.md 56.7](decisions.md#567-the-two-published-api-breaks-are-repaired-not-shipped)). The signal was briefly a nullable type; that broke the published non-nullable field, so it is now the distinguished `const CryptoConfig.eraDefault()` marker as the field's default — same meaning ("whatever this release encrypts with"), published surface intact. Every reader goes through `CryptoConfig.forClient(atClient)` — the one place the era default lives. The SDK deliberately does *not* resolve into the app's preference object: harmless while the default is a const, a per-atSign leak the moment it is not. What SS-4 still owes is the *other* half — building the key ring at init once the default becomes the nskey path | **SS-4** |
| ~~The `_nskeylock` mint/rotate race~~ — **done.** `NskeyMintLock` takes it remote-first, because the atomicity is the atServer refusing a second immutable create; a local-first put would let both enrollments believe they won and collide only at sync. The loser re-reads and adopts rather than waiting | **SS-4** |
| ~~The bench harness `acceptance.md` says lands with B-1~~ — **built 2026-08-04**, `packages/at_client/benchmark/crypto_bench.dart`. Reports three **separately-based** groups and refuses to combine them: *per record* (what every put/get pays once a CK exists — AES-256-GCM vs the legacy AES-256-CTR path), *per (owner, namespace) conveyance* (where PQ actually costs something — X-Wing `pqSeal`/`pqOpen` vs RSA-2048 wrap, paid **once** and then covering every record in scope), and *per authentication* (the ML-DSA-65 ↔ RSA-2048 signature swap). Mixing them is what would produce a headline "PQ is N% slower" from incomparable denominators. **The desktop baseline is now recorded** in [decisions 28](decisions.md#28-the-pq-performance-budget-measured-2026-08-04) — the harness had been run when it was built, but its numbers were never written down, so the acceptance row was asking for a budget that existed nowhere a reader could find it. Headline: at the 256 B size that dominates real traffic, GCM costs **3 µs** more than CTR; the ML-DSA sign a client pays per authentication is **2.7 ms**. **The ceiling is still NOT pinned:** `acceptance.md` requires one reference *low-end* device and the recorded run is a 16-core arm64 Mac, which is the opposite. Nothing here is a regression gate — one desktop run is a baseline, not a threshold | **B-1** |
| ~~`at_chops` `pqOpen` lets an `ArgumentError` escape~~ — **fixed in at_chops 3.4.2** (unpublished): a wrong-length secret key or KEM ciphertext now arrives as `PqOpenException(malformedEnvelope)`. `NskeyProvider`'s client-side guard stays until at_client's floor rises past 3.4.1 | `at_chops` |
| ~~The CK cache and the owner's own nskey privates are process memory only~~ — **half of this was wrong.** Content keys are a genuine cache: the read path re-fetches the `__ck` conveyance record and re-opens it, so a restart costs a round trip, not data. The nskey private is the real exposure, and [decisions.md 21](decisions.md#21-ss-3-where-key-material-lives-and-what-the-substrate-stops-storing-2026-08-03) ruling 1 files it into `AtKeys` on arrival. **Owed:** implement that filing, plus the current-`ckKid` pointer (ruling 2) so a restart stops minting a fresh CK per destination | **SS-3** / **SS-4** |
| ~~`B-1e` does not work~~ — **found and fixed 2026-08-04** ([decisions.md 26](decisions.md#26-uc-a44-a-conveyance-that-loses-the-race-to-its-own-announcement-2026-08-04)). The two-client harness exposed it on its first run: the content-key conveyance was written local-first, so it reached the recipient's atServer only via sync — 31 seconds later in the captured reproduction — while the notification went out immediately over the monitor. The receive path raised `ContentKeyUnavailableException` correctly and the dispatch loop swallowed it at `finer`, dropping the notification silently with no retry. Both notify entry points now route the conveyance remote-first (the same rule as the `__ssenv` ordering fix), and the dispatch `catch` logs at `warning`. **UC-A4.4 is met**, live-covered in `tests/at_end2end_test/test/pq/nskey_notify_test.dart` (split out of `concurrent_notify_test.dart` 2026-08-08). ~~**UC-A3.4 is NOT** — corrected 2026-08-09: both live notify tests are alice→bob, so the SELF direction (alice1→alice2) is asserted against a mock only … owed rather than blocked (#2093)~~ — ✅ **UC-A3.4's self direction is live-proven** (`tests/at_functional_test/test/nskey_self_notify_live_test.dart`, "a self notification reaches a second enrollment and decrypts"). ~~Still open, recorded in 26.3: a notification whose transform throws is gone, with nothing re-delivering it when the missing piece lands~~ — ✅ **for the case that names, closed by the park and re-drive** ([14.30](#1430-a-content-notification-can-outrun-the-key-that-opens-it), [decisions 106.5](decisions.md#106-a-notification-that-outruns-its-key-is-dropped-not-parked-2026-08-16)). ⚠️ The park is typed to `NskeyPrivateUnavailableException` alone (`notification_service_impl.dart:539`), so a transform that throws anything else is still gone with nothing re-delivering it |
| An enrollment authorised for one namespace must be unable to **decrypt** another's nskey data, not merely unable to fetch it. Not testable yet and deliberately not written: nskey privates are per-ring in-memory until the substrate conveys them, so a second enrollment cannot decapsulate anything at all — the crypto half of the assertion would pass vacuously while the test read as covering it | **SS-4** |
| ~~The notify **receive** half has no live coverage~~ — **closed 2026-08-04.** It did need harness work rather than a test, and the lever was `AtClientManager`'s public constructor: one manager per atSign, each owning its own client, `notificationService` and `syncService`, with `AtClientImpl`'s cache keyed by atSign so two *different* atSigns never collide. `ConcurrentClients` (`lib/src/concurrent_clients.dart`) plus `concurrent_notify_test.dart` now show a monitor on bob receiving and **decrypting** what alice sent, live — the existing `notify_test.dart` had worked around the limitation by switching atSigns and polling `notifyList`, which reads the atServer's queue and exercises neither the monitor nor decryption. Negative control run: reinstating the singleton fails with `@alice stopped=true` from `open`'s own guard. **The constraint to respect:** while a `ConcurrentClients` is open, nothing may call `getInstance().setCurrentAtSign` for either atSign — the cached `AtClientImpl` would be handed a fresh `notificationService`, and the symptom is a subscription that never fires, which reads as a product defect | `at_end2end_test` |
| ~~Rename the atSign-level key in code, delete the `root-pqpublickey` variant~~ — **done.** `NskeyRecipientKind` has one member; no Dart source says `pqpublickey`; the cold-start throw now states why there is no PQ target rather than promising a fallback | **B-1c** |
| ~~Enrollment approval reverses direction~~ — **done.** It needed the atServer after all, though far less of it than "multi-repo seam" implied: the *return* leg rides the existing substrate with no verb change, but the atServer made `encryptedAPKAMSymmetricKey` mandatory on `enroll:request`, so an enrollee that wraps nothing could not send a valid request. That check now yields to an advertised key package and stays mandatory otherwise | **SS-2** |
| ~~`_apsk`'s published value becomes a root-signed envelope rather than a bare key~~ — **re-ruled 2026-08-05 by [decisions 39](decisions.md#39-_apsk-rides-the-same-two-stage-ladder-2026-08-05):** the final 3.x publishes the bare value EXACTLY as today (apps parse it), while verify learns the tagged self-describing form 4.x enrollments will publish — built (`parseApskValue`/`verifyEnvelope`) | **RF-2b** |
| ~~Open an in-progress version in `at_chops` and `at_commons`~~ — **done, and renumbered 2026-08-11.** The open headings are now at_chops **3.6.0** and at_commons **5.15.0**; 3.5.0 and 5.14.0 both published from trunk that day. Fold further entries under the new headings | `at_chops` / `at_commons` |
| ~~`_addMetadataToBuilder` is a hand-rolled copier~~ — **done.** `Metadata.copy()` (at_commons 5.14.0) is the canonical converter; the notify path copies wholesale and then clears the few fields a sender must not assert, so a field added upstream travels by default. Now at_commons **5.15.0**, at_client's floor `^5.15.0` | `at_commons` |

**Open, not yet grilled.** Two threads the 2026-08-03 session raised and did not
settle: what the signing root signs beyond `_apsk`; and the key-transparency publication
mechanics (when a root is submitted, and what a client does if the log is unreachable at
mint). A third — cheap PQ-capability discovery — is now half-answered:
`CryptoRuntime.isReadyFor` exists and shares the write path's advertisement cache, and the
per-owner resolution memo of
[decisions.md 19.4](decisions.md#194-cost-and-the-three-lifetimes) removes the per-item
cost. What is still unanswered is the *first* contact with a recipient, which remains one
round trip per `(recipient, namespace)`.

**Ruled and built 2026-08-03: nskey resolution in nested namespaces**
([decisions.md 19](decisions.md#19-nested-namespaces-the-nskey-is-resolved-by-walking-up-2026-08-03)).
A sender resolves **most-specific first and walks up** — `d.c.b.a`, then `c.b.a`, then
`b.a`, then `a` — sealing to the first published nskey and failing only when the walk is
exhausted. The walk mirrors the atServer's own suffix authorisation, so it cannot cross a
boundary the server would have held: `rw` on `a` *does* imply access to `d.c.b.a`, which is
the direction the walk goes. It is required rather than optional, because AtCollection
composes sub-collection namespaces with a per-**item** id.

`NskeyResolver` owns the walk and its miss-memory; `CkManager` shares one with the data
provider so both ends of a write agree on where the content key lives, and
`CryptoRuntime.isReadyFor` inherits it. The wire carries the answer: `appMetadata.ns` on
every nskey-path record, plus `ckNs` on a data value. A prerequisite finding is that
`AtKey.fromString` splits at the **last** dot, so a multi-segment namespace is
unrecoverable from the wire string at all — which is why `ns` exists, and why the AAD now
binds the record's full address rather than namespace and key separately.

Both live suites gained multi-segment coverage, seeded at a **multi-segment app namespace**
on purpose: with a single-segment one the last-dot split lands on the right answer by
coincidence. That trap is not hypothetical — it made the first version of the unit test
pass against a deliberately broken build.

*Test runners:* use the committed `tests/*/runLocal.sh`. They pull the virtualenv image;
ad-hoc copies that skip `docker compose pull` will silently test a stale atServer.

**PR chunks (ordered).** B-1 is the plan's only flat-XL project, so it lands as up to five sequential PRs,
`B-1a`…`B-1e`. `B-1a` is an enabler that closes no scenario of its own and may land in the same PR as
`B-1b`; every other chunk merges only with its own green acceptance scenario. `B-1` stays the project id —
the chunk ids are its PR breakdown, not new projects.

| Chunk  | Scope                                                                                                                                                     | Closes                    |
|--------|-----------------------------------------------------------------------------------------------------------------------------------------------------------|---------------------------|
| `B-1a` | **Layer 3** — the `at/symmetric/AES/GCM` provider + the CK cache keyed `(owner, namespace, ckKid)`                                                        | — (enabler)               |
| `B-1a′`| **The CK manager** — `ensureCurrent` + the `PreparesWrites` seam. Pulled forward ahead of the substrate work: without it `put` cannot succeed at all, so every later chunk is blocked behind a provider that always throws | — (enabler)               |
| `B-1b` | **Layer 2** — the `at/nskey` CK-conveyance provider, **self-data direction only**; the nskey private is supplied by a **test fixture**, not the substrate | UC-A3.1                   |
| `B-1c` | **Cold-start fails cleanly** — a distinct exception naming the recipient and namespace, an opt-in legacy fallback, and a pre-flight capability query. There is no PQ target to fall back to. **Landed on the spike branch** | UC-A3.3                   |
| `B-1d` | **Cross-atSign** — `plookup` discovery of the recipient's published nskey; re-fetch on decapsulation failure                                              | UC-A4.1, UC-A4.2, UC-A4.3 |
| `B-1e` | **`providerId` on notification frames**                                                                                                                   | UC-A3.4, UC-A4.4          |

**Why `B-1b` uses a fixture.** The fixture-supplied nskey private is what lets `B-1b` land **before SS-4**.
It inverts the dependency order **for demonstration only**: the production path is unchanged — SS-4 delivers
the nskey private over the substrate, and the fixture is deleted the moment SS-4 lands. This is the point of
the split: it produces the program's **first green acceptance scenario** (UC-A3.1) without waiting for the
substrate. Nothing downstream of `B-1b` may depend on the fixture.

**Where the B3 capability marker lands.** *(Historical — the marker was removed by
[decisions 36](decisions.md#36-the-rollout-is-the-apps-decision-capability-markers-built-examined-and-removed-2026-08-05).)*
`providerId` on stored values comes with `B-1a`/`B-1b`; `providerId` on
the notification frame with `B-1e`. The marker's own lifecycle was R-1's, was built
there, and was removed with it.

**Acceptance → [acceptance.md](../acceptance.md):** self + shared round-trips byte-exact for text and binary;
UC-A3.1, UC-A3.3 (self cold-start fails, distinctly), UC-A4.1/A4.2/A4.3; B3 per the rewritten catalogue
(capability stage writes legacy, active stage writes the data path); UC-A3.4 / UC-A4.4 (providerId travels
on the notification frame). Each chunk
carries the scenarios listed against it in the chunk table.
**Effort:** XL — the one project above the ~1–3 PR norm, hence the five-chunk breakdown (~M each).
**Watch-outs:** `recipientKind` has exactly one member, `nskey`, used for self and inbound alike — one key
both ways, so there is no self-vs-inbound variant, and the atSign-level signing root is not a member because
nothing is ever encapsulated to it; no bare `nskey` providerId. The record owner (`sharedBy`, which the
HPKE `info` binds) and the nskey owner (`sharedWith ?? sharedBy`, which selects the key and scopes the CK
cache) are **different atSigns** on any inbound record — conflating them is why cross-atSign reads fail
([decisions.md](decisions.md) section 15). Sweep
`expectAsync`/listener counts for the new notification-frame shape. The CK-conveyed-once rationale
(decision (a)) and the recipientKind enumeration are in [design.md](../design.md).
**coversD1:** D1-B B1–B4.

---

## 7. Phase RF — existing-client retrofit (RF-1, RF-SRV, RF-2b, RF-2c)

> **Re-positioned 2026-08-05
> ([decisions 40](decisions.md#40-rf-srv-is-the-mechanism-the-whole-model-stands-on-2026-08-05)):
> RF-SRV is ON the D1-GA critical path.** The three-scenario model's "each app
> upgrades its own enrollment, on its own schedule" conjugates this verb in every
> scenario, and without it the only upgrade path is a human approving from another
> device. RF-2b/RF-2c remain the client orchestration that rides it.

The substrate facts (pull/push
are dual facets) are stated once in [section 5](#5-phase-ss--secret-sharing-substrate-ss-1a-ss-1b-ss-1c-ss-2-ss-3-ss-4)
— not re-explained here.

**Retrofit design facts (stated once; rationale in [decisions.md](decisions.md)):**

1. **No per-APKAM-key delete.** A 1:1:1 record holds exactly one key. Legacy retirement = the RF-SRV
   enrollment-expiry cap + the existing `enroll:revoke`.
2. **Retrofit = a FRESH, self-spawned, AUTO-APPROVED enrollment (not a mutation).** An authenticated pre-PQ
   client submits `enroll:request` with a **new enrollmentId** on its authenticated connection (**no OTP**);
   the server validates the requested namespaces are a **subset** of the authenticating enrollment,
   auto-approves, **copies** the old enrollment's expiry (or null) to the new one, and **caps** the old
   enrollment to `min(now + server-config grace, its existing expiry)` **without removing it**; each cloned
   pre-PQ keyfile retrofits to its **own distinct enrollmentId**.
3. **The old enrollment ages out** — no in-place key delete, no delete-after-verify ordering.
4. **ML-DSA APKAM auth is used** (RF-2b mints ML-DSA, authenticates under the new id).

### RF-1 — `requestSecret(name)` confirm against the hardened substrate · at_client · S
**Goal:** confirm the generic by-name pull primitive against the hardened store.
**Builds on:** SS-3. ⚠️ the primitive already shipped in the SS-0 baseline (PR #2037) — RF-1 is a thin
**tests-only confirmation** scoped to **generic** named secrets (nskey/pqpublickey-payload + UC-B5.1 defer to
SS-4/B-1). **May simply merge into SS-3.**
**Deliverables → [design.md](../design.md)** (requestSecret pull primitive): confirm generic by-name request →
serve flow + revocation-serve via the `answerSecretRequests` policy / server gate (not an
`excludeEnrollmentIds` param on the serve path — it has none).
**Acceptance → [acceptance.md](../acceptance.md):** generic by-name round-trip + revocation-serve.
**Effort:** S.
**Watch-outs:** the selfEncryptionKey-wrap shortcut is rejected (not PQ-safe); CK rotation does not use this.

### RF-SRV — atServer: authenticated self-retrofit enroll (auto-approve + namespace-subset + expiry copy/cap) · at_secondary_server, at_server_spec · L
**Goal:** the server half the retrofit depends on.
**Builds on:** the existing authenticated-request + CRAM auto-approve templates.
**Deliverables → [design.md](../design.md)** (authenticated self-retrofit flow): on an `enroll:request`
arriving on an **APKAM-authenticated** connection (`authType==apkam`, resolvable approved enrollmentId; not
CRAM, not legacy PKAM) with a new enrollmentId and **no OTP**, the server (1) validates the requested
namespaces are a **subset** of the authenticating enrollment's (reject escalation); (2) **auto-approves**
(model on the CRAM branch's state=approved / skipCommit-pubkey / set-enrollmentId mechanics **without** its
`__manage`+`*`:rw grant); (3) **copies** the authenticating enrollment's expiry (or null=never) to the new
enrollment; (4) **caps** the old enrollment's expiry to `min(now + serverConfig grace, its own posture's
expiry)` **without removing it** — the cap **re-arms on every sibling retrofit** (ruled in
[decisions 42](decisions.md#42-the-to-define-list-ruled-2026-08-05) item 3, landed on the spike), so the
legacy credential retires one grace period after the *last* clone upgrades; (5) stores/returns
`EnrollParams.metadata` (per SS-1a/b). New `at_secondary_config` grace-duration knob (alongside
`enrollmentExpiryInHours`), ratified at 720h.
**Acceptance → [acceptance.md](../acceptance.md):** authed `enroll:request` (new id, no OTP) → auto-approved (no
pending notification), key package stored; escalating namespaces → `UnAuthorized`; the new enrollment
inherits the old's expiry; the old enrollment's ttl is capped (record still present, still authenticates
until the cap elapses); both suites.
**Effort:** L.
**Watch-outs:** net-new is the `apkam`-authType auto-approve branch (NOT the CRAM `*`:rw grant), the
requester-keyed subset check at request time, the expiry copy + old-enrollment ttl cap, and the config knob.
**2026-08-05 additions ([decisions 40](decisions.md#40-rf-srv-is-the-mechanism-the-whole-model-stands-on-2026-08-05)):**
the child records its **parent** enrollment and revocation **cascades** to
descendants (a stolen keyfile must not spawn a survivor); distinct
`(appName, deviceName)` per cloned device is *client-side guidance* (RF-2b) — the
server deliberately does **not** refuse duplicates on the APKAM branch; the new
enrollment id lands in the keyfile that already holds the legacy material.
**Ruled 2026-08-05 ([decisions 42](decisions.md#42-the-to-define-list-ruled-2026-08-05)
items 1-4, landed on the spike where noted):** wire shape frozen as built plus two
deltas (duplicate check skipped on the APKAM branch; `namespaces` mandatory
non-empty) — both landed; the expiry cap **re-arms** per sibling retrofit at
**720h** — landed; revocation gets **two modes** (revoke-compromised cascades
eagerly over `parentEnrollmentId`; retire does not, for planned migration off a
shared keyfile), unrevoke is non-cascading, and `parentEnrollmentId` is exposed in
`enroll:fetch`/`enroll:list` — the walk is still to implement; and the spawn
moment **signs and conveys the child's chain link** whenever the parent credential
can, so scoped enrollments are born anchored (new requirement, mirrors the
approve-time conveyance).
**coversD1:** D1-F retrofit (server); legacy retirement via expiry + revoke.

### RF-2b — at_client: mint PQ (ML-DSA) APKAM + key package, then authenticated auto-approved self-retrofit `enroll:request` · at_client, tests · L
**Goal:** the client half — mint a PQ APKAM and retrofit via a fresh auto-approved enrollment.
**Builds on:** RF-SRV, SS-3, SS-4, P-2.
**LANDED 2026-08-05** ([decisions 43](decisions.md#43-rf-2b-lands-and-what-the-first-genuine-ml-dsa-pkam-found-2026-08-05)):
`AtSelfEnrollmentRequest` (at_auth), ML-DSA PKAM signing (at_chops 3.4.2),
`signEnvelope` mldsa65 + builder `signingAlgo` (at_client), per-enrollment
AtChops resolution threaded through `authenticate`. Live-proven end to end in
`self_enrollment_retrofit_live_test.dart`. Landing it surfaced and fixed three
defects (the atServer had never verified a genuine ML-DSA signature; at_chops'
mldsa verify was async-poisoned; record-authoritative fell through to the wire
claim for pre-field enrollments). What was handed on to RF-2c — Monitor
signingAlgoType threading, the (AtClient, enrollmentId) kpid staleness, and the
UC-B1.x scenario orchestration — has since landed there in full.
**Deliverables → [design.md](../design.md)** (PQ-APKAM mint + self-retrofit): the client (authenticated with
its pre-PQ keypair) mints — once per keyfile under a host-local lock — an ML-DSA signing keypair + X-Wing
enc keypair, builds the key package, and submits `enroll:request` with a **new enrollmentId** on the
authenticated connection carrying the package as `EnrollParams.metadata` + `signingAlgo=mldsa65` (no OTP).
On the auto-approved response it writes `.atKeys` under the new enrollmentId. Each cloned pre-PQ keyfile
retrofits independently to its **own distinct enrollmentId** (one key package per enrollment, 1:1:1).
**Acceptance → [acceptance.md](../acceptance.md):** mint at most once per keyfile (lock under concurrency); a
self-retrofit auto-approves (no human, no OTP, no conveyance) and the client immediately PKAM-auths with the
ML-DSA key under the new id; two clones of one pre-PQ keyfile reach **distinct** enrollmentIds; requested
namespaces ⊆ the authenticating enrollment's.
**Effort:** L.
**coversD1:** D1-F (PQ-APKAM via fresh auto-approved enrollment).

### RF-2c — at_client: retrofit orchestration (old enrollment ages out) + full e2e · at_client, tests · L
**Goal:** the orchestration + end-to-end retrofit, with the old enrollment ageing out.
**Builds on:** RF-2b, RF-SRV, SS-4, SS-2.
**Deliverables → [design.md](../design.md)** (retrofit orchestration): authenticate with the pre-PQ keypair →
RF-2b self-retrofit → switch the client to the new enrollmentId's `.atKeys` — the **same file**, which keeps
the legacy encryption keypair, `selfEncryptionKey` **and the RSA APKAM**
([decisions 37](decisions.md#37-legacy-key-material-is-retained-until-the-ecosystem-is-pq-not-the-atsign-2026-08-05)).
The old enrollment **ages out**
via the RF-SRV expiry cap (or an explicit `enroll:revoke`). There is no readiness
flip — writing PQ remains the app's release decision. One key package per enrollment (1:1:1).
**Acceptance → [acceptance.md](../acceptance.md):** (e2e `@ce2e*`) the new ML-DSA
enrollment authenticates; previously shared secrets stay openable; the old enrollment stops authenticating
once its capped expiry elapses (or after `enroll:revoke`) — **not** via an in-place key delete;
seal-once-reaches-every-host; revoke/expire-one-host; sync-less wake-up.
**Effort:** L.
**LANDED 2026-08-05** ([decisions 44](decisions.md#44-rf-2c-the-switch-over-and-what-it-cost-to-make-a-client-pq-2026-08-05)
for the switch-over, [45](decisions.md#45-the-retrofit-rows-and-the-five-defects-the-first-end-to-end-run-found-2026-08-05)
for the rows): `selfRetrofit(...)` runs submit → re-authenticate → switch, and
the client's signing algorithm (resolved from the keyfile; since 2026-08-09 an
impl-only getter — [decisions 58.2](decisions.md#582-signingalgotype-comes-off-the-interface-the-key-material-answers)
took it off the `AtClient` interface) reaches the verb
connection, the monitor, sync, and `wrapAndSign`; key-package adoption is
enrollment-scoped. The 20.3 kpid staleness is discharged by construction (a
switch builds a NEW `(atSign, enrollmentId)` client; the enrollment never
changes under a live one). The **UC-B1.x and UC-B2.x e2e rows are green** —
`tests/at_end2end_test/test/pq/retrofit_e2e_test.dart` and
`retrofit_retirement_e2e_test.dart`: the signing-root step in-flow (privileged
mint, clone request+verify, scoped skip), two clones of one pre-PQ keyfile
reaching distinct enrollment ids, and the capped legacy enrollment refused with
`AT0028` while an un-retrofitted sibling still authenticates. Writing them
found five defects, all fixed with differential tests — the retrofit never
minted a root; no holder could answer a pull after a restart; the start-time
sweep destroyed the requests it could not yet answer; a scoped enrollment could
be handed the signing root; and a conveyed root private was filed unchecked.
(The self-notification finding from 44 is **resolved** — a race in the test,
not a delivery bug. See [decisions 44.3](decisions.md#443-two-findings-from-the-live-run).)
**Still owed against this project: nothing.** UC-B0.1 (a PQ client aborting
against a *legacy* atServer) stays skipped and is blocked on the **harness** —
no suite here can build an atServer image without the retrofit verbs — so
re-scope or waive it as UC-A3.2 was.
**coversD1:** D1-F end-to-end (retrofit via fresh enrollment).

---

## 8. Phase R/B — rollout, rotation, retirement & versioning (R-1, SH-1, B-2, KE-1, B-3, ON-1, R-2)

**Stated once:** at_auth 4.0 (S-5) is a **different major at a different time** from at_client 4.0 (R-2).
The forward-secrecy/rotation levers and the `disallowLegacyEncryption` flag semantics live in
[design.md](../design.md); the high-level 3.x-off / 4.x-on trajectory is in [roadmap.md](../roadmap.md); the
rotation-policy ruling is in [decisions.md](decisions.md).

### R-1 — `disallowLegacyEncryption` flag (default false) · at_client · ✅ DELIVERED 2026-08-05, scope shrunk
**Goal (as delivered):** the PQ-write flag — how an app *states* "never write legacy".
**Builds on:** B-1.
**What happened to the rest** ([decisions 36](decisions.md#36-the-rollout-is-the-apps-decision-capability-markers-built-examined-and-removed-2026-08-05)):
**C1** (readiness-marker lifecycle) and **C2** (per-destination negotiation) were
**built, proven at three layers including a live two-atSign flip, and removed the
same day** — the three-scenario examination showed the rollout is the app's
decision, made by which build it ships, and the SDK never chooses a scheme. **C3**
(per-namespace strict mode + seal-and-hold) was deferred unbuilt: no consumer asked
for more than the named cold-start refusal plus the explicit fallback.
**Delivered:** **D1-D** — `disallowLegacyEncryption` on `AtClientPreference`, final
at construction (immutable, constructor parameter), **default false**, SHOUT at
creation when false, governs only legacy-provider *encryption* (legacy read +
`shouldEncrypt=false` + public-key signing unaffected), checked at selection *and*
at encryption, and it wins over `allowLegacyCryptoFallback` (a cold start under the
flag is refused, not reached under legacy). Additive within 3.x.
**Acceptance:** flag=true → legacy-only destination **refused** never downgraded,
explicit legacy request refused, legacy read still works, flag immutable —
`disallow_legacy_encryption_test.dart` + the rewritten cross-cutting invariant.
**coversD1:** D1-D. (D1-C's migration story is now [decisions 36](decisions.md#36-the-rollout-is-the-apps-decision-capability-markers-built-examined-and-removed-2026-08-05)'s
two-release ladder + SH-1's self-heal, not machinery.)

### SH-1 — key-material self-heal: nskey pull initiator + approve-time push + chain sweep · at_client · M *(**LANDED** 2026-08-05)*
**All four wires have production call sites** — start-time pull
(`at_client_impl.dart` `_fileConveyedKeysAndAnchor`), on-miss pull
(`nskey_seeding.dart` `requestMissingPrivates`, `pq_signing_root.dart`
`requestPrivateIfAbsent`), approve-time push (`enrollment_service_impl.dart`
finally calls `conveyHeldPrivatesTo`), and store hydration — and the trigger
points are ratified as the definition by
[decisions 42](decisions.md#42-the-to-define-list-ruled-2026-08-05) item 11.
Live-proven in `nskey_self_heal_live_test.dart`.
**Goal:** make [decisions 38](decisions.md#38-key-material-self-heals-mint-if-absent-else-pull-2026-08-05)'s
invariant true in code — every enrollment converges on the key material it is
entitled to, with no human step and no ordering luck.
**Builds on:** SS-2/SS-3/SS-4 (the substrate + filing are all built; this is wiring
with tests, the same shape as the root-pull initiator in decisions 31).
**Why it exists:** neither of Decision #4's push methods
(`shareAllSecretsWithEnrollment`, `conveyHeldPrivatesTo`) had a caller, and the
nskey privates had no pull initiator — the only delivery was the mint-time push, so
every enrollment created after a mint was stranded (`no nskey private held`) with
nothing to retry. The ordinary second device hits this, not just the cloned-keyfile
scenario.
**Deliverables:** (a) start-time pull — for each authorised namespace whose
published nskey generation this client lacks, `requestSecretsFromNamespace` for the
private (any holder answers; store-and-forward both ways); (b) on-miss request in
the `at/nskey` decrypt path — fire the pull, rethrow the typed exception, so a
mid-run arrival heals without a restart; (c) approve-time push — the approver
conveys its held nskey privates for the approved namespaces
(`conveyHeldPrivatesTo`, finally called); (d) the **chain sweep** — a fully
privileged client signs approval-chain links for enrollments that lack them
([decisions 38](decisions.md#38-key-material-self-heals-mint-if-absent-else-pull-2026-08-05).3).
**Acceptance:** a second enrollment that missed the mint-time push acquires the
private with **no re-mint** (functional, live); the sweep anchors a
scoped enrollment approved by a legacy parent; unit coverage for all four wires.
**Effort:** M.
**Watch-outs:** the pull's trigger points are **ruled**
([decisions 42](decisions.md#42-the-to-define-list-ruled-2026-08-05) item 11): the
built four (start-time current-generation, on-miss exact-kid, approve-time push of
all held generations, mint-time push) ARE the definition; the rotation initiator,
rotation-time conveyance, and `excludeEnrollmentIds` threading move to B-2.

### B-2 — nskey rotation + revocation (CK rotation = coarse FS, nskey-keypair rotation = PCS) · at_client · L — **LANDED 2026-08-06**
**Goal:** the two rotation levers + revocation composition — the **D1 GA** rotation slice.
**Landed** on `gkc-pq-d1-spike` ([decisions 47](decisions.md#47-b-2-lands-two-levers-and-the-difference-between-excluding-and-revoking-2026-08-06)):
`PublishedNskeyKeyRing.rotate` + `NskeyRotation` (B5b, with rotation-time
conveyance and `excludeEnrollmentIds`), `NskeyRotation.revokeEnrollmentAndRotate`
(B6, revoke-first because **the ordering is the enforcement** — an exclusion
alone is a courtesy at the rotating client), `CkManager.rotateContentKey` +
`ContentKeyEviction` (B5a, the delete-and-evict FS lever, wired on every
client's sync service). Two defects found in the enrollment path on the way
(a thrown AT0015 and a malformed `_apsk` both escaped a skip that documented
itself as covering them), and one privilege distinction the first live run
forced: rotating needs `rw` on the namespace, revoking needs `__manage`.
All four UC-A5.x rows green. Rails: at_client 967 unit, functional 137, e2e 50.
**Builds on:** B-1 + SH-1 + **(RF-1 + SS-3)** for the per-enrollment substrate fan-out (1:1:1). ⚠️ **depends
on RF-1+SS-3, NOT the full RF-2** (Open decision #C) — so **D1 GA does not wait on the auth retrofit**.
Implements four rulings from [decisions 42](decisions.md#42-the-to-define-list-ruled-2026-08-05):
last-holder-lost recovery = explicit rotation, rw-on-namespace, history stays lost (item 5); clones share
fate — revoke cuts every clone, exclude excludes every clone or none, per-device revocability only via
RF-SRV re-enrollment (item 6); plus the three pieces moved out of the self-heal (item 11): the **rotation
initiator** (nothing in production calls `mintAndPublish` for an existing namespace), rotation-time
conveyance of the new generation, and threading `excludeEnrollmentIds` into the nskey pull/answer paths
after a revocation.
**Deliverables → [design.md](../design.md)** (rotation/revocation levers): **B5a** CK rotation (O(1), on
ordinary sync, delete old `__ck` + evict; default RETAIN, FS-mode is the delete+evict knob); **B5b**
nskey-keypair rotation (O(n) PCS / per-APKAM revocation: take `_nskeylock.<ns>@<owner>`, mint a new nskey
keypair, **overwrite** `public:__nskey.<ns>@<owner>` with the new advertisement, convey the new
private per-APKAM via the substrate excluding revoked, release; old privates retained = history-on, not
per-message FS; a late joiner is pushed the current generation only and pulls older ones on demand via
`requestSecret`, addressable because each `__ck` names its `nskeyKid`); **B6** revocation
composition
(auth-revoke + rotate-exclude + optional history re-encrypt [D2]); inbound cross-atSign FS is **bilateral**
(documented trade-off).
**Acceptance → [acceptance.md](../acceptance.md):** UC-A5.1 (both levers); UC-A5.2/A5.3 + B6 (revoked/excluded
enrollment can't read post-rotation; bilateral inbound FS); functional nskey self+shared / rotation /
mixed-scheme / cold-start / revoke+rotate-exclude; e2e at_talk chat scenario. **▶ at_client 3.14.x = D1 GA.**
**Effort:** L.
**Watch-outs:** don't conflate the levers (CK rotation does NOT ride the per-APKAM substrate).
**coversD1:** D1-B B5/B6.

### KE-1 — a selectable KEM and a negotiated construction · at_chops, at_client, at_auth · L — **LANDED 2026-08-07**
**Goal:** make the key-establishment algorithm a **deployment choice** and the sealing construction a
**negotiated** one, so the wire can move without a flag day and a FIPS-facing deployment has an answer.
**Landed** on `gkc-pq-d1-spike`, `6a85fad05`…`f3e5b3686`
([decisions 50](decisions.md#50-two-kems-by-configuration-one-construction-by-negotiation-2026-08-07)):
`AtKemAlgorithm.newSeed`/`keyPairFromSeed` + `MlKem1024PureDartAlgo` + `pqSeal ver 0x03`
(**at_chops 3.6.0**, unpublished); `SecretSharingAlgos` gains `ml-kem-1024`, both RFC 9180 suites,
`sealVersionFor`/`suiteForKeyAlgo`/`openableSuitesFor`/`kemFor`/`kemForSuite`, and joins the **main
barrel**; `AtClientPreference.keyEstablishmentAlgorithms` (singular `keyEstablishmentAlgo` when
this shipped; a list since KE-2) is read by `KeyPackageRegistration` and
`enrollmentKeyPackageBuilder`; `sendEnvelope` seals under the **recipient's** `alg` at the strongest
suite both sides list; `NskeyAdvertisement`/`ResolvedNskey` carry `alg` **and** `suites` and
`PublishedNskeyKeyRing` mints under the preference; `at/nskey/MLKEM1024/AES/GCM` is the second
conveyance provider id, registered on every client whatever this atSign mints. `at_auth` gains
`CryptographicMaterialAlgorithm.mlKem1024` (additive — that enum's documented contract is never to reject an unknown
value). Rails: at_client **1012** unit, at_chops **465**, functional **138**, e2e **50**.
**Builds on:** B-1 (the conveyance path it re-versions), SS-2/SS-3 (the key package it negotiates
against), SS-4 (the nskey it advertises), and plan-backlog
[14.5](#145-a-write-side-envelope-version-selector-in-at_chops--done) (the write-side version selector).
Not on B-2 — but it lands after it, and rotation is the **only** moment an atSign's advertised algorithm
can change, so the two are read together.
**Deliverables → [design.md](../design.md)** (advertised-key shapes; the seal's versions live in
[seal-spec.md](../seal-spec.md)): the nskey advertisement gains `alg` + `suites`; the key package gains
`suites` **derived from its own `keys[]`**; the sender resolves KEM-from-`alg`, suite-from-intersection,
`pqSeal` version from suite; both receive paths resolve the KEM from the envelope's declared suite rather
than assuming the hybrid; keys are persisted as **seeds** with the algorithm alongside
(`PersistedEncKey.encSeed` + `keyAlgo` — `PersistedApkamKeys` held the pair directly until
[14.18](#1418-the-remaining-d1-initial-development-sequence) step 5 made it a list) and expanded
on the way out.
**Acceptance → [acceptance.md](../acceptance.md):** UC-A2.4 (the configured KEM is what an enrollment mints
and advertises, and an existing key keeps its own), UC-A3.5 (the nskey advertisement names its KEM and
what it can open), UC-A4.5 (the sender follows the recipient, not its own preference), UC-A4.6 (an absent
`suites` means exactly the construction that existed when it was written), UC-A4.7 (no shared construction
is a refusal). The live wire assertion — that the negotiated version is the version on the atServer — is
`tests/at_functional_test/test/secret_sharing_delivery_test.dart`.
**Effort:** L.
**Watch-outs:** **at_chops 3.6.0 is unpublished and is a MINOR, not a patch** — `newSeed`/`keyPairFromSeed`
are abstract members on the exported `AtKemAlgorithm`, so any external `implements` breaks; at_client's
floor is `^3.6.0` and workspace resolution masks that from every local build. KE-1's content moved off
3.5.0 when trunk published that number on 2026-08-11 with unrelated content, so a pub.dev check showing
3.5.0 live is **not** this gate. A published
`suites`/`legacy…Suites` constant **must never grow** — an advertisement is fetched by senders who act on
the claim immediately. And an enrollment's KEM is frozen at `enroll:request`
([14.6](#146-the-enrollment-records-metadatakeypackage-is-a-one-way-door)): changing the preference takes
effect on the next enrollment, never on this one.
**coversD1:** D1-A (a second KEM primitive + `ver 0x03`) and D1-B (the conveyance and envelope paths
negotiate their construction); discharges plan backlog
[14.2](#142-a-version-on-the-two-signed-payloads--done),
[14.4](#144-a-suites-list-on-the-key-package--done) and
[14.5](#145-a-write-side-envelope-version-selector-in-at_chops--done).

### KE-2 — `enroll:update` + a multi-kpid receiver · at_commons, **every atServer implementation**, at_client · L — [#2133](https://github.com/atsign-foundation/at_client_sdk/issues/2133)
**Goal:** KE-1 made the KEM selectable and the construction negotiable; this makes the choice
**revisable**. An enrollment can amend its own `metadata.keyPackage` after approval, so a package can gain
a key, an envelope shape can be rolled forward, and an unparseable package stops being terminal.
**Builds on:** KE-1 (the `keys[]`/`suites` agility it makes reachable), SS-2 (the `EnrollParams.metadata`
passthrough it complements).
**Ruled → [decisions 68](decisions.md#68-the-enrollment-record-stops-being-a-one-way-door-enrollupdatemetadata-2026-08-10)**
(eight rulings, the verb's shape, and the site-by-site receiver change list).
**Deliverables — server half: BUILT** on at_server `gkc-apsk-auto-publish` (`ab38b884`), 919/919 unit and
210/210 functional. ✅ **Re-derived 2026-08-15: that branch and that SHA are both MERGED to
at_server's `origin/trunk`** — naming a branch here reads as work still in flight, and it is not.
Re-derive rather than trust:
`git -C ~/dev/atsign/repos/at_server merge-base --is-ancestor ab38b884 origin/trunk && echo MERGED`. One alternation entry on `syntax.dart`'s `enroll` pattern (verified not to disturb
`force`/`listNamespace` or the `request`/`listns` captures); a `case 'update'` handler that is
**self-only** (the connection's `enrollmentId` must equal the target — an explicit exception to
`isAuthorized`'s "no enrollmentId ⇒ full permissions" default, so an owner or legacy-PKAM connection is
refused), **approved-state-only**, and **per-key set** rather than whole-map replace; the server keeps no
opinion on the contents.

⚠️ **Two things this entry used to say are no longer true**, both from
[91](decisions.md#91-signature-agility-the-apkam-auth-key-stops-being-the-enrollments-signing-key-2026-08-11)
ruling 13. The verb is **`enroll:update`**, not `enroll:updateMetadata`, and it reaches
`apkamPublicKey`, `signingAlgo`, `apsk` and `metadata` rather than metadata alone —
`namespaces` and the approval state stay permanently out of reach, because a self-only
operation must not be able to widen its own grant. And it **does** take new `EnrollParams`
fields: `apsk` and `apkamPublicKeySignature`, both shipped in at_commons 5.14.0.
Parity across atServer implementations is a tracked follow-up so it cannot silently diverge.
**Deliverables — client half (the larger one): ✅ DONE 2026-08-13** as
[14.18](#1418-the-remaining-d1-initial-development-sequence) step 5. The receiver holds a **set** of KEM
keypairs and answers at every held kpid: `PersistedApkamKeys` is a list of `PersistedEncKey`,
`keyPackageMaterials` returns every material for the enrollment, `EnvelopeAddressing` has
`regexForAny`/`sweepRegexForAny`, the sweep/subscribe/marker paths watch every address, and `pqOpen` is
handed **the secret selected by `envelope.kid`**. A replaced kpid is retained — an envelope written before
the update still opens — and it *is* marked retired, which is what stops a sender addressing it while the
holder keeps opening what already named it (95 rulings 6–9 supersede this entry's "never retired").
The `to.kpid != kpid` self-check was already fixed: `_isSelf` compares `enrollmentId`.
**What this leaves for B-2** is the writer that creates the state. **Updated 2026-08-13:** the
`enroll:update` *caller* now exists — `AtEnrollment.update` /`EnrollmentUpdateRequest`, and
`EnrollmentUpdateRequest.metadata` merges per-key into the record
([14.18](#1418-the-remaining-d1-initial-development-sequence) step 16).
✅ **Updated 2026-08-19: the part that gives it something to send is BUILT.**
`KeyPackageMinting` mints a new KEM key, marks the outgoing one retired and
republishes the package. ⚠️ **This paragraph ended "nothing rotates yet, and
nothing calls `update` in production" until that landed** — a startup step now
does, on any client whose configured key-establishment list has changed.
✅ **[#2133](https://github.com/atsign-foundation/at_client_sdk/issues/2133) was retitled to
`enroll:update` and given a status block on 2026-08-18**, which is also when `blockers.dart`'s `ke2`
constant stopped saying "neither half is built" — it had said so since the client half landed, and it
is the string anyone greps to find out what KE-2 owes.
✅ **The receiver-side algorithm list AND the writer are BUILT, 2026-08-19.**
[Ruling 113](decisions.md#113-pqposture-three-postures-and-the-rollout-they-drive-2026-08-18)
ruling 8 asked for two posture-defaulted algorithm lists. The **sender-side**
one shipped with 14.39 (`sealsToKeyAlgorithms`); the **receiver-side** one
landed here as `AtClientPreference.keyEstablishmentAlgorithms`, replacing the
singular `keyEstablishmentAlgo` — together with the writer that gives it
meaning, which is why the two were held to land in one place.

⚠️ **This entry said the writer was "missing" and that a list before it would
"carry entries nothing acts on".** Both were true until `KeyPackageMinting`
landed. What exists now:

- **`KeyPackageMinting`** (`lib/src/secret_sharing/key_package_minting.dart`),
  a `PqClientBootstrap` step placed after `mintInUseSigningKeys` — the package
  is signed by whatever key `_apsk` advertises, so signing it first would sign
  under the key that start is about to retire. It mints an encapsulation
  keypair for every algorithm the list names and the enrollment lacks, retires
  every one it holds that the list no longer names, re-signs the package with
  all of them and sends `enroll:update`.
- **It files before it publishes** — the inverse of `SigningKeyMinting`, and
  the asymmetry is the design. An encapsulation key advertised before its
  private half is filed makes senders seal to a key nobody holds, and those
  writes are durable. A signing key inverts both arms. Proven by mutation:
  swapping the order reddens exactly the ordering test.
- **The list defaults to one entry** (`[x-wing]`), not to everything the build
  supports, because a shorter list here refuses nobody while an extra entry
  costs a keypair carried for the life of the enrollment. An **empty** list is
  refused, where an empty `sealsToKeyAlgorithms` is not.
- **The first entry is the primary**: anything minting a single key — an
  nskey, a fresh package key — takes it, so a reorder changes what the atSign
  mints next and `rolloutDifferencesFrom` compares the list order-sensitively.

⛔ **The "one residual" [#2133](https://github.com/atsign-foundation/at_client_sdk/issues/2133)
records — `enrollment_symmetric_key.dart:148` still filtering on the singular
`regexFor(kpid)` — is EXAMINED AND CORRECT, 2026-08-19. Do not "fix" it.**
That scan runs inside `enrollmentApkamSymmetricKeyResolver`, during enrollment
bootstrap, and its `kpid` comes from `_keyPackageHalves` — one key, chosen
before any client exists. At that moment the enrollment being created holds
exactly one package key by construction: `enrollmentKeyPackageBuilder` has just
minted it, and `KeyPackageMinting` cannot have run, because it is a startup
step on an already-approved client. The approver seals to what the enrollment
advertised, which is that key. Widening the scan to `regexForAny` would make it
watch addresses this enrollment never advertised, for a key nobody sealed to.

✅ **The two acceptance rows are PROVEN, 2026-08-19**, cited to
`tests/at_functional_test/test/key_package_amendment_live_test.dart`: UC-A2.5
as a differential (a client configured for one KEM leaves its record alone; a
client configured for two amends it at startup, and the control arm is what
shows both began with one key), UC-A2.5's per-key metadata merge, and UC-A2.6's
two refusals with the accepted arm in the same session. The acceptance
burn-down is back to **0 skipped**, and the `ke2` blocker constant is deleted —
`catalogue_test.dart` forced that in the same commit, because a blocker
guarding nothing tells whoever greps it the project owes no scenarios.

✅ **All three are proven live, 2026-08-24**, in
`tests/at_functional_test/test/key_package_amendment_live_test.dart` and pinned
as clauses from `a2_enrollment_test.dart`. ⚠️ This read "**Three clauses those
rows assert are NOT proven, and are recorded rather than quietly claimed** —
plan **14.19 item 36**: a superseded kpid's envelope still opening, a peer
negotiating to its preferred key, and UC-A2.6's revoked-enrollment gate."
Proving them corrected two of the three: nothing is *superseded* by an
amendment (a key is joined and the original stays `active`), and the
"revoked-enrollment gate" is not a check inside `enroll:update` — the outcome
comes from the revoked enrollment being unable to authenticate at all, plus
every other connection being refused as not-self.

⚠️ **A real defect was found only by reasoning about the live path**, after the
unit suite was green: `KeyPackageMinting` read tagged key material only, and
`enrollmentKeyPackageBuilder` files an enrollment's first package **untagged**
— it runs before the atServer assigns an id. So the writer saw every fresh
enrollment as holding nothing and minted a duplicate key on first startup. The
unit fixture had tagged the material; production does not. Two nskey live rows
failed against the broken version and pass against the fix, in the same
environment — which is what settles the attribution.

**Still owed:** parity across atServer implementations, tracked separately.

**Acceptance → [acceptance.md](../acceptance.md):** UC-A2.5 (a package gains a second KEM key; a peer negotiates
to it; envelopes at the old kpid still open) and UC-A2.6 (a foreign enrollment, and an owner connection, are
both refused).
**Effort:** L.
**Watch-outs:** the multi-repo seam is useless landed on one side; the self-only exception is the whole
security argument, so its differential test must prove a *refused* arm, not only an accepted one; and the
dozen dartdocs across `at_client` that state the freeze are the sweep list for the landing commit.
**coversD1:** retires plan backlog [14.6](#146-the-enrollment-records-metadatakeypackage-is-a-one-way-door).

### B-3 — selfEncryptionKey + shared_key.* retirement, phases 1-3 · at_client, **at_secondary_server**, at_auth · L — [#2128](https://github.com/atsign-foundation/at_client_sdk/issues/2128)
**Goal:** retire the legacy self-encryption key (a distinct project from B-2's rotation work).
**Builds on:** B-2.
**Deliverables → [design.md](../design.md)** (selfEncryptionKey retirement, **re-timed by
[decisions 37](decisions.md#37-legacy-key-material-is-retained-until-the-ecosystem-is-pq-not-the-atsign-2026-08-05)**):
**Phase 1** stop using
selfEncryptionKey for new writes (default → nskey path); **phase 2** lazy re-encrypt on touch (+ optional
background sweep, per-atSign progress observable); **phase 3** stop conveying it — ⚠️ needs an **at_server
change**: `enroll:approve` currently *mandates* `encryptedDefaultSelfEncryptionKey`; relax to optional. The
**server-side tolerance can land early**, but the **client-side stop is
ecosystem-gated, not version-gated**: clients keep minting and conveying legacy
material until the stop-by-default release (to-define item 10). (Phase 4
stop-existing is that release's, **no longer R-2's**.)
**Acceptance → [acceptance.md](../acceptance.md):** a touched legacy value lazily re-encrypts (providerId
legacy → at/symmetric/AES/GCM); migration progress query; a post-migration `enroll:approve` omits the self
key and the enrollee onboards without it.
**Effort:** L.
**coversD1:** D1-B B7 phases 1-3.

### 14.38 `activate_cli` cannot administer a PQ-native atSign

Found 2026-08-18 driving `activate_cli` against a throwaway virtualenv.
Evidence, reproduction and the rejected alternatives are in
[#2161](https://github.com/atsign-foundation/at_client_sdk/issues/2161); this
row is the work.

✅ **DONE 2026-08-19**, live-green: the CLI functional pack 17/17 against a
locally built `at_virtual_env:local`.

An atSign activated PQ-native cannot then run `otp` or
`list`: both fail with `RangeError`, because the connection signs the PKAM
challenge as RSA-2048 with an ML-DSA key. `otp` is where a second enrollment
starts, so a PQ-native atSign cannot enrol a second app.

at_client resolves the algorithm correctly and `RemoteSecondary` stamps it on
the lookup. `AtOnboardingServiceImpl._initAtClient` then overwrote it from the
preference.

⚠️ **This row used to say the method "serves both" the `onboard` and
`authenticate` callers. `onboard()` never called it.** Its two callers are
`enroll()` and `authenticate()`, and that is what makes the fix a condition
rather than a deletion: enrolment holds a lookup the service built for a
keypair minted moments earlier with no keyfile yet, so the preference is the
only source there is, while authentication adopts the client's own lookup and
the client has already read the keyfile. Deleting the stamp outright, as change
1 first proposed, breaks enrolment — proven by mutation, not by argument.

**Three changes, agreed with gkc 2026-08-18.**

1. ✅ **DONE 2026-08-19** — in two steps, and the first was not enough.
   14.39's CLI commit changed *which* preference field the overwrite read
   (posture's `authenticationKeyAlgorithm` rather than the deprecated
   `signingAlgoType`) and this row recorded that as done. The overwrite itself
   survived, so #2161 stayed live: `at_activate otp`, `list` and `spp` build
   their client through `createAtClient`, which named no posture, so the
   posture was `legacy` and the stamp claimed rsa2048 for an ML-DSA
   enrollment. The stamp is now conditional — key material wins for a lookup
   adopted from the client, the preference still decides for one the service
   built, and `hashingAlgoType` stays unconditional on both paths because no
   key material says how a challenge is hashed (and because that assignment is
   what resets a cached client's lookup, which the `list` after a
   passphrase-protected authentication depends on — the pack caught this).
2. ✅ **DONE 2026-08-19.** The site was **not** in
   `AtClientImpl.encryptUnencryptedFile`/`_uploadFile`, as this row claimed;
   neither symbol exists anywhere in the tree. It was in the deprecated
   `AtClient.stream()`, which the row's own grep recipe found correctly. All
   three sites in `AtClientImpl` that open a connection now go through
   `buildRemoteSecondary`, so carrying the client's identity is a property of
   the class; a unit rail pins that there is exactly one construction left and
   that it is the builder.
3. ✅ **DONE 2026-08-19.** Both tests in `pq_native_onboard_test.dart` now
   drive their remote commands on a client from a fresh `authenticate()` under
   a **bare** preference — what `createAtClient` hands every non-onboarding
   command — never on the activation client, which agrees with itself. The
   rsa2048 arm is a legacy activation of `@egbiometric🛠`, and each arm states
   its own resolved algorithm so a run in which they converged fails rather
   than passing while measuring nothing.

⛔ **Still parked, and the reason has changed.**
`AtLookupImpl.signingAlgoType` initialises to `rsa2048` (find it by symbol:
`git grep -nP 'SigningAlgoType signingAlgoType = ' -- packages/at_lookup/lib`),
so any site that forgets authenticates with the wrong routine silently. Making
it required at construction would let the compiler enumerate every site. This
was parked for want of an open at_lookup version — and 3.7.0 is now open and
unpublished, so **that** blocker is gone. The new one is bigger: `AtLookupImpl`
is a published constructor with callers outside this tree, so a required named
parameter takes at_lookup to **4.0.0**, and every in-tree defective site is now
fixed by other means (14.38 change 2, and the audit that found the only other
unstamped sites were in `SyncIsolateManager`, deleted 2026-08-19 as item 32 —
so **every** surviving construction in at_client now carries an identity, and a
required parameter would enumerate nothing). Reopen when at_lookup has a
major in flight for its own reasons; needs a ruling, not a decision taken here.

✅ **The posture argument reaches every command as of 2026-08-19** —
`--posture legacy|pqReady|pqActive`, `--signingAlgoType` removed.

⚠️ **This paragraph used to say that closed the silent-no-op half of
[#2161](https://github.com/atsign-foundation/at_client_sdk/issues/2161) "by
construction — there is no flag left to be a no-op". It did not.** For a day
`--posture` reached every *parser* while only `onboard` and `enroll` read the
value; the other twelve commands built their client through `createAtClient`,
which named no posture. The argument had reproduced the exact defect it
replaced, and the tests were green throughout because they asserted the parser
accepted it. `createAtClient` now takes a `posture`, all eleven call sites pass
it, and a rail checks the value reaches a client rather than a parser.


### ON-1 — PQ-native greenfield onboarding + legacy-interop opt-out · at_client, at_client_flutter · M — **ACCEPTANCE COMPLETE 2026-08-08** ([decisions 52](decisions.md#52-on-1-a-greenfield-atsign-starts-where-a-retrofit-ends-2026-08-08))  *(critic gap — UC-A1.1; amended by decisions 37)*
**Landed:** `pqNativeOnboard` (at_client) over `AtOnboardingRequest.signingAlgoType`
+ `mintLegacyMaterial` + `metadataBuilder` and a PQ-native mint (at_auth 4.0.0-rc1).
**UC-A1.1 is green live** — the ML-DSA APKAM re-authenticates on a fresh
connection with no RSA APKAM in existence. Backlog
[14.1](#141-the-signing-roots-keys-shape--deadline-the-first-root-we-keep) was
ruled in the same pass, because this is the project that makes roots permanent.
**UC-B4.2 followed on 2026-08-08** —
`tests/at_functional_test/test/pq_legacy_interop_live_test.dart`, three
self-activated atSigns, both directions and the opt-out. It landed in the
*functional* pack rather than `tests/at_end2end_test`, because that pack runs in
CI against long-lived cicd atSigns and so cannot CRAM-activate anything; the row
had been labelled for the wrong layer since it was written. Running it opened
[14.12](#1412-a-mintlegacymaterialfalse-atsign-cannot-write-a-public-record):
the legacy-interop opt-out is honoured at activation but leaves an atSign that
cannot write a public record at all.
**The `at_onboarding_cli` half landed 2026-08-08**, live-covered in
`tests/at_onboarding_cli_functional_tests/test/pq_native_onboard_test.dart` —
a CRAM activation under a post-quantum posture against a real atServer
(`--signingAlgoType mldsa65` when this landed; `PqPosture.pqReady` since
2026-08-19, when the argument was replaced by `--posture`),
asserting all three products of a PQ-native activation together. That pack runs
against the virtualenv container in CI, so this is CI-reachable coverage. It is
deliberately **one test asserting three things**: the products are
all-or-nothing, and a suite that could go green with two of them is not
guarding the property that matters.

The work was not a flag. `AtOnboardingPreference` already carried
`signingAlgoType` and the impl already threaded it into `_atLookUp` but *not*
into the `AtOnboardingRequest`, so setting it gave ML-DSA PKAM signing against
an RSA APKAM; and threading it into the request alone would have been worse
still — an ML-DSA APKAM with no key package and no signing root, unrepairable
because `metadata.keyPackage` is written once by the creating `enroll:request`.
So at_client now exports the two halves (`makeActivationPqNative`,
`mintSigningRootAfterActivation`) and both `pqNativeOnboard` and the CLI use
them, rather than the CLI carrying a second copy of the definition.

Two things the live run found, neither of which unit tests would have:
`authenticate` threw `Null check operator used on a null value` from its
local-secondary key back-up, which dereferenced the flat APKAM fields a PQ
keyfile leaves empty; and a `!= rsa2048` test for "is this post-quantum" would
have silently forced ML-DSA on a caller asking for `ecc_secp256r1`, which this
package supports.

**Still owed:** the `at_client_flutter` call site.
**Goal:** a brand-new atSign onboards PQ-native (the root of Part-A coverage).
**Builds on:** RF-2b (PQ-APKAM mint) + SS-4 (pqpublickey).
**Deliverables → [design.md](../design.md)** (PQ-native onboarding, **amended by
[decisions 37](decisions.md#37-legacy-key-material-is-retained-until-the-ecosystem-is-pq-not-the-atsign-2026-08-05)**):
at CRAM onboarding mint a **PQ (ML-DSA) APKAM** keypair (no RSA APKAM required for
auth); immutable-create `public:pqpublickey@<atSign>`; **and still mint the legacy
RSA encryption keypair + `selfEncryptionKey`, and publish `public:publickey` — by
default**. Whether this atSign will need legacy is determined by the apps that
adopt it, unknowable at onboarding. The **legacy-interop flag becomes an opt-OUT**,
named by [decisions 42](decisions.md#42-the-to-define-list-ruled-2026-08-05)
item 10: **`bool? mintLegacyMaterial` on `AtOnboardingRequest`** in at_auth
(minting happens at onboarding, before an AtClient exists). `null` resolves to the
release default — true through at_client 4.x, false from the stop release; explicit
false → PQ-only, no RSA `public:publickey`, no legacy material.
**Acceptance → [acceptance.md](../acceptance.md):** UC-A1.1 (PQ-native onboard:
APKAM=pq, pqpublickey immutable, KP registered, legacy material present and
published by default); UC-B4.2 (legacy-peer interop works by default in both
directions; only the opt-out refuses it).
**Effort:** M.
**coversD1:** Catalogue Part-A root + Decision #1 as amended by decisions 37 / UC-B4.2.

### R-2 — at_client 4.0.0: apply the postQuantum posture defaults · at_client · M  *(re-timed by decisions 37; reframed by decisions 70)*
**Goal:** PQ-safe on every write path by default (the final cutover).
**Builds on:** B-2 + RF-2c + S-6 (R-1's flag is delivered). **Gated on the ecosystem floor** (last published downstream versions).
**Deliverables → [design.md](../design.md)** (the v4 flip): change
`AtClientPreference`'s default posture from `PqPosture.legacy` to
`PqPosture.pqActive` — one edit that flips every rollout axis
(era `CryptoConfig` → nskey writes, `disallowLegacyEncryption` → true — SHOUT
if re-enabled false, envelope emission → JWS v2, posture-built enrollments →
pq key exchange, argless retrofits → ML-DSA). The at_auth-side hard defaults (the
default `AtEnrollmentRequest` constructor is legacy mode — pq is the separate
`AtEnrollmentRequest.pq(...)` — and mechanism-level `signingAlgo`) are
at_auth's own major to flip, separately.
The legacy provider itself **stays** (reads forever).

⚠️ The "TWO coupled edits" hazard (established 2026-08-08 — flipping
`disallowLegacyEncryption` alone refuses **every** encrypted write, because
the migration era default's `defaultProviderId` IS `legacy`, and
`providerIdFor` refuses a legacy id under the flag; the suite's own
`disallow_legacy_encryption_test.dart` asserts exactly that failure) is now
**structural**: the posture carries the era choice and the flag together, so
the default-posture flip cannot make one edit without the other
([decisions 70](decisions.md#70-workstream-a-capstone-pqposture-the-five-flags-as-one-value-2026-08-10)).
⚠️ **This paragraph used to say local and namespace-less keys route to legacy
and are refused, so "the SDK's own namespace-less internal writes need their own
decision".** Both halves are now settled and neither gates R-2: `local:` records
are written unencrypted and exempt
([decisions 107](decisions.md#107-a-local-record-is-not-encrypted-and-the-legacy-refusal-exempts-it-2026-08-17)),
and the namespace-less case named there — a legacy recipient's `shared_key.*` —
never reaches the refusal at all
([14.33](#1433-closed-the-shared_key-refusal-was-never-reachable)). The one
genuine instance is a key-construction bug in `NotificationService.send()`
([14.35](#1435-notificationservicesend-throws-away-the-namespace-it-was-given)).

⚠️ **The "dead-code removal" bullet was wrong on both halves** and is dropped.
(a) The two `package:encrypt` files are live production code, not leftovers:
`encryption_util.dart` is exported from the public barrel and called from every
`put` (IV generation), and the file's own note says the task is *migrating* to
at_chops, not deleting — with 9 more importers inside at_chops besides. (b) All
299 `deprecated_member_use` findings are at_client *consuming* at_chops/at_auth
deprecations (`AtChopsKeys` 65, `AtChopsUtil` 59, `AtChopsImpl` 45, `AtChops`
44, `AtChopsKeys.create` 38 — 251 of 299 from those five); removing at_client's
own 75 `@Deprecated` members would move the count by zero. See
[14.11](#1411-deprecated_member_use-findings-across-the-workspace).

⚠️ **Test blast radius, before touching the default.** The shared `MockAtClient`
holds a default-constructed `AtClientPreference`, so flipping the default turns
every mock in the suite strict — `MockAtClient()` is constructed 61 times across
38 files — and one cross-cutting acceptance arm asserts a capability-build mock
resolves to `legacyCryptoProviderId`, which would then throw. Repo-wide there
are 191 bare `AtClientPreference()` sites whose meaning changes with no site
having been edited. **B7 phase 4 ("stop generating
`selfEncryptionKey`, drop it from the AtKeys model") is NO LONGER a 4.0 action** —
[decisions 37](decisions.md#37-legacy-key-material-is-retained-until-the-ecosystem-is-pq-not-the-atsign-2026-08-05):
legacy material is retained until the *ecosystem* is PQ, so the stop is a later,
ecosystem-gated release — ruled in
[decisions 42](decisions.md#42-the-to-define-list-ruled-2026-08-05) item 10: the
next major after this one (5.0.0 at the earliest), cut only when every first-party
downstream's last published major writes PQ by default and the server tolerance for
absent legacy fields is deployed everywhere, with `mintLegacyMaterial` resolving
null→false from that release and **repair-on-first-demand** making an early stop
recoverable.
**Acceptance → [acceptance.md](../acceptance.md):** the seven rollout axes under the flipped default
posture — UC-C1.1 (era), C1.4 (key exchange), C1.5 (retrofit), C1.2 (refusal) and
C1.6 (the grouped posture); **C1.3 (envelope) is withdrawn** — [`decisions.md` 95](decisions.md#95-the-envelope-keeps-one-shape-and-a-retained-key-says-so-2026-08-12) removed the axis it tested, written for R-2 by the capstone; plus legacy read still works (UC-B5.2);
full unit/functional/e2e green. **One thing UC-C1.x cannot reach, which R-2 owes:** a live postured
CRAM onboard (`pqNativeOnboard`'s posture consult is pinned at the parameter level only)
([decisions 70.1](decisions.md#701-the-review-harvest-the-postures-claims-corrected-two-consults-get-their-reds-2026-08-10)).
⚠️ **There used to be a second, and it has been withdrawn twice over.** It first
named "the sync and notification watermarks" as internal writes owing a decision: wrong,
those are `local:` records, now written unencrypted, and the fix had to land in D1 because
R-2 is a pure default-flip that cannot carry code
([decisions 107](decisions.md#107-a-local-record-is-not-encrypted-and-the-legacy-refusal-exempts-it-2026-08-17)).
It was then rewritten to name the *non-local* namespace-less writes — a legacy recipient's
`shared_key.*` most obviously — and that was wrong too: nothing routes one through the
refusal, so it cannot be refused
([14.33](#1433-closed-the-shared_key-refusal-was-never-reachable)).
**No client-side blocker remains for R-2**; the gates that stand are the ecosystem floor
and [decisions 37](decisions.md#37-legacy-key-material-is-retained-until-the-ecosystem-is-pq-not-the-atsign-2026-08-05).
**▶ at_client 4.0.0.**
**Effort:** M.
**Watch-outs:** different major / different time from at_auth 4.0 (S-5). Don't remove the legacy provider.
Don't stop minting legacy material — that is the later release's flip, not this one's.
**Gate, checked against pub.dev 2026-08-08 — R-2 is not startable, and not for a
reason in this repo.** The "ecosystem floor" is not merely unpinned, it is
structurally unreachable until the 3.x capability release ships and each
downstream re-publishes against it:

| Package | Published | Pins `at_client` | What has to happen first |
|---|---|---|---|
| `at_chops` | **3.5.0** (2026-08-11) | — | publish **3.6.0** (KE-1's seed API), row 3 of the publish table. 3.5.0 published from trunk and carries `RsaSignatureAlgo` and the PQ length validation — **not** KE-1 |
| `at_auth` | 3.3.0 | — | publish 3.4.0 (in-tree, unpublished) |
| `at_client` | **3.14.0** | — | publish the D1 GA minor — 3.14.0 carries none of the nskey path |
| `at_onboarding_cli` | 1.16.0 | `^3.10.0` | re-publish against the GA minor |
| `at_client_flutter` | 1.1.4 | `^3.11.0` | re-publish against the GA minor |
| `at_cli_commons` | 3.1.1 | `^3.7.0` | re-publish against the GA minor |

Every downstream range is `^3.x`, which **excludes 4.0.0** — so cutting the
major today would strand all three on a client that cannot write PQ, which is
the opposite of what the flip is for. R-2 stays last by construction; what this
entry can be is accurate about the two edits and the blast radius, which it now
is.
**coversD1:** D1-D D3 + D1-B B7 phase 4.

---

## 9. Phase D2 — referenced only (D2-1, out of D1 GA)

### D2-1 — carve `at/pqmls` provider + D1-E shape fixes · at_client · L
**Goal:** carve the v1 `at/pqmls` group provider and apply the D1-E shape fixes.
**Builds on:** **#1930** (the M0 seam — *not* B-1; the provider uses only seam types) + **SS-2** (the
per-APKAM substrate the group reuses). Off the D1 critical path; **must not gate D1 GA.**
**Deliverables → [design.md](../design.md)** (at/pqmls structural shape carried forward): carve the v1
`at/pqmls` group provider keyed onto the per-APKAM substrate (via `EnrollmentDirectory.listForNamespace` +
`KeyPackage`); apply D1-E fixes — lift membership into `SecureGroup`, binary-safe, rename
`PairwiseGroup`→`SelfGroup` (scope the grep to `PairwiseGroup`, not `Pairwise`); pin the provider wire id
to `at/pqmls`.
**Acceptance → [acceptance.md](../acceptance.md):** round-trips via the seam (text + binary byte-exact);
per-APKAM re-key (rotate distributes epoch keys to each enrollment's KeyPackages); rename sweep clean.
**Effort:** L.
**coversD1:** **D1-E only** (the provider itself is D2).
**Watch-outs:** D2 work; the v1 epoch engine is thrown away at the MLS swap — invest only in the
carried-forward interface shape. **D2 proper (pq-mls engine, Group Delivery Service, identity hardening) is
out of scope here** — see [roadmap.md](../roadmap.md) for the D2 trajectory.

---

## 10. Cross-cutting: publish gates, critical path, waves/parallelism, testing

### (a) Publish gates
- `at_chops` (P-1, P-2, **KE-1**) and `at_commons` (SS-1a) publish **before** `at_server`/consumers bump pins.
- ⚠️ **`at_chops` is at 3.6.0 in-tree and unpublished** (KE-1). **3.5.0 published on 2026-08-11 from
  trunk and does NOT contain KE-1** — it carries `RsaSignatureAlgo` and the PQ length validation. The
  spike had been claiming 3.5.0 for KE-1's content and moved to 3.6.0 on the trunk merge (`95584f818`);
  do not read a published 3.5.0 as this gate being discharged. It is a **MINOR, not a patch**:
  `newSeed`/`keyPairFromSeed` are **abstract members added to the exported `AtKemAlgorithm`**, so any
  external `implements AtKemAlgorithm` stops compiling. Every implementation in this repository is a
  `final class … implements` and was caught at compile time; nothing outside gets that. at_client's floor
  is `^3.6.0`, which workspace resolution satisfies from source — so this gate is invisible to
  every local and CI build and must be discharged explicitly before the at_client D1 GA publish.
- ⚠️ **`at_commons` is at 5.15.0 in-tree and unpublished.** 5.14.0 published 2026-08-11 carrying the
  `enroll:update` grammar, `EnrollParams.apsk` and `.apkamPublicKeySignature` ([#2137](https://github.com/atsign-foundation/at_client_sdk/pull/2137));
  the spike's `Metadata.copy()` moved to 5.15.0 in the same merge, and at_client's floor is `^5.15.0`.
- `at_auth` is split **additive-3.3.0** (S-1; 3.2.0 was consumed by the network-timeout release) then **breaking-4.0.0** (S-5) so the `AtKeys`/`AtKeysIo`
  extend-in-place bakes before the barrel cut.
- `at_client` stays **minor 3.14.x** through D1 GA; the v4 flip (R-2) is the final gated cutover.

#### What still has to be published, in order

**This is the single reference for publish order.** `implementation-plan.md`'s
`After D1` block and [#1889](https://github.com/atsign-foundation/at_client_sdk/issues/1889)
point here rather than restating it, because they each carried their own copy
and all three drifted apart.

Measured 2026-08-19 against pub.dev and every pubspec in the tree. Re-derive
before acting: a same-value version bump merges with no conflict, so a number
here can be attached to different content than the one on pub.dev.

| Order | Package | In-tree | Published | Note |
|-------|---------|---------|-----------|------|
| 1 | `at_chops` | **3.6.0** | 3.5.0 | Stays a **minor** — [decisions 109](decisions.md#109-at_chops-360-stays-a-minor-no-major-bump-for-this-release-2026-08-18). Two source-breaking changes, neither with a consumer |
| 2 | `at_commons` | **5.16.0** | 5.15.0 | Opened for `Metadata.copy()` |
| 3 | `at_auth` | **3.4.0** | 3.3.0 | ⚠️ Carries 3 source-breaking changes and its own major question is **open** — ruling 109 settles at_chops only |
| 4 | `at_client` | **3.14.1** | 3.14.0 | ⚠️ The GA release carries the whole nskey data path, so re-derive the slot at publish time. A patch bump understates it; row 7 below assumes a minor |
| 5 | `at_onboarding_cli` | **1.17.0** | 1.16.0 | Already open in-tree, independently of S-6 |
| 6 | `at_client_flutter` | **1.1.5** | 1.1.4 | Already open in-tree, independently of S-6 |
| 7 | `at_cli_commons` | 3.1.1 | 3.1.1 | **No version opened yet.** Needs one before it can take the new constraints |

`at_lookup` is **not** on this list: in-tree 3.6.1 equals published 3.6.1, and
nothing in the remaining work touches it. Opening 3.6.2 is gkc's call and
ruling 109 removed the reason to.

The table below is the historical record of how each slot was reached, kept
because its row numbers are cited elsewhere. Read it for provenance, not for
what to publish next.

**Package versions & release sequencing** (single reference — publish in dependency order; two majors —
`at_auth` 4.0 (S-5, WASM split) and `at_client` 4.0 (R-2, the flag flip) — at different times):

| #  | Package             | Bump                          | Project(s) | Why |
|----|---------------------|-------------------------------|------------|-----|
| 1  | `at_chops`          | minor `3.2.1 → 3.3.0` **(published 2026-06-23, done)** | P-1    | stateless functional core + HPKE `pqSeal`/`pqOpen`; `@Deprecated AtChopsImpl` shim |
| 2  | `at_chops`          | minor `3.3.0 → 3.4.0` **(published 2026-07-17, done)** | P-2 | #2030 (`at_chops_ffi` barrel + `AtPqc` + `AtSignatureAlgorithm`) landed the 3.4.0 bump on trunk 2026-07-03 (+ #2046); P-2's `mldsa65` verify branch (#2056, 07-06) and #2039 (AES-GCM FFI, 07-09) folded into the same slot, which then published. Minor under the one-time semver exemption ([decisions.md](decisions.md) 2026-07-03) |
| 2b | `at_chops`          | minor `3.4.1 → 3.5.0` **(published 2026-08-11, done)** | — (trunk) | `RsaSignatureAlgo`; PQ key/ciphertext/signature length validation across both backends; `MlDsa65FfiAlgo.verifyBytes` throws `StateError` on an incapable libcrypto. **Not a PQ-program release** — it took the version number the spike had been claiming, which is why row 3 moved up |
| 3  | `at_chops`          | minor `3.5.0 → 3.6.0` **(in-tree, UNPUBLISHED)** | KE-1 | `AtKemAlgorithm.newSeed` + `keyPairFromSeed`; `MlKem1024PureDartAlgo`; `pqSeal ver 0x03` (RFC 9180 at KEM `0x0042` / HKDF-SHA384 / AES-256-GCM); RFC 9180 Base mode as `ver 0x02`; `HkdfSha384`; `ChaCha20Poly1305Algo`. ⚠️ **MINOR because the two seed methods are abstract members on the exported `AtKemAlgorithm`** — an external `implements` must add them. at_client pins `^3.6.0`, and workspace resolution hides the gap |
| 4  | `at_commons`        | minor `5.11.0 → 5.12.0` **(published 2026-07-04, done)** | SS-1a | `EnrollParams.metadata` + `signingAlgo`; flattened `listns`; pkam `mldsa65` literal. *(at_commons has since published 5.13.0, 5.14.0 and 5.15.0 outside this programme, and 5.16.0 is open in-tree — see the ordered list above.)* |
| 5  | `at_auth`           | minor `3.2.0 → 3.3.0` **(published stable 2026-07-17, done)** | S-1 | additive: extend `AtKeys` in place (deprecate legacy); `AtKeysIo` runtime persistence; `InMemoryAtKeysIo`. The rc1 → stable promotion is **closed** (re-verified against pub.dev 2026-08-08), so S-6 and SS-2's at_auth work have the stable version they pin against |
| 5b | `at_auth`           | minor `3.3.0 → 3.4.0` **(in-tree, UNPUBLISHED)** | KE-1, ON-1 | opened 2026-08-03 (`936241d8f`): `CryptographicMaterialAlgorithm.mlKem1024`; the `.atKeys` passphrase envelope derives from a random per-file salt (was salted with the passphrase itself). **This is the open at_auth slot** — ON-1's `mintLegacyMaterial` folds in here rather than opening a new version |
| 6  | `at_auth`           | **major `3.4.x → 4.0.0`**     | S-5        | breaking WASM cut: `FileAtKeysIo` → `at_auth_io.dart`; default removed; registrar → `package:http` |
| 6b | `at_lookup`         | minor `3.6.1 → 3.7.0` **(in-tree, UNPUBLISHED)** | 14.39 | `AtConnectionMetaData.authenticatedAsEnrollmentId` + `authenticatedAt`, set by every path in `AtLookupImpl` that authenticates and by `Monitor._authenticateConnection`. Minor because it is purely additive and `AtConnectionMetaData` is not exported from the barrel, so nothing outside can `implements` it. ⚠️ **at_client now pins `^3.7.0`**, so row 7 cannot publish before this does — the same shape as its at_chops gate. at_auth still pins `^3.6.0` and is unaffected |
| 7  | `at_client`         | minor `3.14.x → 3.15.x`       | S-2…B-2, KE-1 | `at_auth ^4.0.0`; `CryptoContext.keys`; nskey data path; rotation; the selectable KEM. **= D1 GA**. ⚠️ **3.13.0 and 3.14.0 both published 2026-07-17** so the GA slot has moved off 3.14.x; trunk is already 3.14.1. For compatibility purposes the baseline is **3.13.0** ([`decisions.md` §91.4](decisions.md#914-what-is-released-and-therefore-what-must-still-be-read)) — re-derive the target minor at execution against pub.dev. ⚠️ **S-2's `CryptoContext.keys` (#2076) is on trunk but unreleased** — it merged after 3.14.0 published, so the next at_client release is the first that carries it. ⚠️ **gated on rows 3 and 6b** — this release cannot go out against an unpublished `at_chops 3.6.0` (a published 3.5.0 does not discharge that gate) nor against an unpublished `at_lookup 3.7.0`, which its own pubspec now pins at `^3.7.0` |
| 8  | `at_client`         | **major `3.15.x → 4.0.0`**    | R-2        | default posture → `PqPosture.pqActive` (every axis, [decisions 70](decisions.md#70-workstream-a-capstone-pqposture-the-five-flags-as-one-value-2026-08-10)); plus the normal major-version deprecation cleanup (orthogonal to the rollout, [decisions 56.4](decisions.md#564-from-the-pq-projects-view-40-is-final-3x-with-different-flag-defaults)). *(selfEncryptionKey stop-existing moved to a later ecosystem-gated release, [decisions 37](decisions.md#37-legacy-key-material-is-retained-until-the-ecosystem-is-pq-not-the-atsign-2026-08-05))* |
| 9  | `at_onboarding_cli` | minor `1.16.0 → 1.17.0`       | S-6        | `at_auth ^4.0.0`; imports `FileAtKeysIo` from `at_auth_io.dart`; explicit injection. 1.16.0 published 2026-07-17, so 1.17.0 is a clean next slot |
| 10 | `at_client_flutter` | minor `1.1.4 → 1.2.0`         | S-6        | `at_auth ^4.0.0`; `file_picker` imports `at_auth_io.dart` |
| 11 | `at_cli_commons`    | minor (constraint bump)       | S-6        | consumes the new `at_onboarding_cli` / `at_client` (transitive at_auth) |

**Dependency-floor bumps (at_client's own pins).** at_client's constraints on trunk are `at_chops ^3.0.0`
and `at_commons ^5.9.0`; both floors rise during D1:

| at_client pin | Floor bump          | Lands at | Why |
|---------------|---------------------|----------|-----|
| `at_chops`    | `^3.0.0 → ^3.3.0`   | SS-0     | the substrate baseline needs the published `pqSeal`/`pqOpen` (3.3.0) — landed with #2037 |
| `at_commons`  | `^5.9.0 → ^5.12.0`  | SS-1c    | the flat `listns` grammar + `EnrollParams.metadata` (5.12.0) |
| `at_chops`    | `^3.3.0 → ^3.5.0`   | KE-1     | the first at_client call to `newSeed`/`keyPairFromSeed` — **raised in the same commit as the first use** (`042fea1d9`), because workspace resolution would otherwise let a consumer resolve an older sibling and get a package that does not compile |
| `at_chops`    | `^3.5.0 → ^3.6.0`   | trunk merge `95584f818` | trunk published 3.5.0 with unrelated content, so KE-1's surface moved to 3.6.0 and the floor followed |
| `at_commons`  | `^5.14.0 → ^5.15.0` | trunk merge `95584f818` | same collision on the `Metadata.copy()` slot: 5.14.0 published carrying `enroll:update`, so the copier moved to 5.15.0 |

⚠️ Workspace resolution wires `at_chops`/`at_commons` as path deps, so a too-low floor still resolves green
locally **and** in CI — these floor bumps must be made **explicitly**, not inferred from a passing workspace
build.

### (b) Critical path to D1 GA
`#1930(done) → P-1 + S-2 → SS-1a → SS-1b → SS-1c → SS-2 → SS-3 → SS-4 (+ P-3) → B-1 → R-1(delivered) → SH-1(done) + RF-SRV(server done) + RF-2b(done) → B-2(done) → KE-1(done) → ON-1(client half done) → R-2 + S-3`
(D1 GA: rebuild = universal reader, one flag = PQ writer, opt-in rotation).
**KE-1 sits on the path rather than beside it** for one reason only: it moved the wire. Two modern peers
now exchange `ver 0x02` where they exchanged `0x01`, and an enrollment's KEM is frozen at
`enroll:request`, so every enrollment created after KE-1 and before GA carries the shape GA ships. It also
put an **unpublished `at_chops 3.6.0`** in front of the at_client GA publish (row 3 of the table above).
**Branch state (2026-08-08):** `gkc-pq-d1-spike` is **pushed**, and is 168 commits ahead of
`origin/trunk` and **17 behind**. The behind-count is no longer trivially docs-only, so the merge back
is worth costing before ON-1 rather than after. It has **no PR**, so nothing runs CI on it.

**Everything up to and including SS-3 is landed as of 2026-08-03** (SS-1c/SS-2/SS-3 on `gkc-pq-d1-spike`, plus [at_server#2739](https://github.com/atsign-foundation/at_server/pull/2739) for SS-3's server half — **corrected 2026-08-13 from #2736, which was closed as superseded and never merged**). **`SS-4`'s signing chain landed 2026-08-04** — mint, root-private conveyance, self-anchoring and the graded walk, all live-covered. **B-1 landed too, and R-1 was delivered 2026-08-05 as the flag alone** ([decisions 36](decisions.md#36-the-rollout-is-the-apps-decision-capability-markers-built-examined-and-removed-2026-08-05)); **SH-1, RF-SRV's server half, RF-2b and RF-2c's switch-over all landed 2026-08-05** ([decisions 42](decisions.md#42-the-to-define-list-ruled-2026-08-05)–[44](decisions.md#44-rf-2c-the-switch-over-and-what-it-cost-to-make-a-client-pq-2026-08-05)), and **B-2 landed 2026-08-06** ([decisions 47](decisions.md#47-b-2-lands-two-levers-and-the-difference-between-excluding-and-revoking-2026-08-06)) with all four UC-A5.x rows green. **KE-1 landed 2026-08-07** ([decisions 50](decisions.md#50-two-kems-by-configuration-one-construction-by-negotiation-2026-08-07)) — the selectable KEM, the negotiated construction, and plan-backlog 14.2/14.4/14.5 discharged — so the path now waits on **ON-1**, **R-2** and **S-3**. RF-2c's UC-B1.x e2e rows are done; two named residuals are left: RF-SRV's revocation cascade (server) — `parentEnrollmentId` is stored but `enroll:revoke` does not yet walk descendants ([decisions 42](decisions.md#42-the-to-define-list-ruled-2026-08-05) item 2) — the **at_chops 3.5.0 publish** that KE-1 put in front of the GA release, and a
**revocation-visibility lag** on the atServer ([14.9](#149-a-revoked-enrollment-can-still-authenticate-briefly)).
Separately, `at_lookup` 3.6.1 ([PR #2127](https://github.com/atsign-foundation/at_client_sdk/pull/2127),
branched from trunk) is **DONE** — corrected 2026-08-13, having said "is open and
needs merging" for five days after it was neither: the PR merged 2026-08-08 and
`at_lookup` 3.6.1 is published on pub.dev. It was never a GA gate.
**Off-path (parallel):** `RF-2b → RF-2c` (RF-1 confirm), `B-3`, `ON-1`, `S-5 → S-6`, `D2-1`, `KF-1`
(builds on S-3), and the final `R-2`.

### (c) Waves / parallelism
The wave-1 → wave-2 boundary is **soft** — the "waves" are parallelism groupings, not barriers; the actual
gating is the per-project dependency list. **The substrate has no remaining publish gate** — its only publish
dependency, `P-1`/`pqSeal` on `at_chops` 3.3.0, **shipped to pub.dev 2026-06-23**; `S-1`/`S-2`/`S-3`
(WP2/WP3/WP4) do **not** block Wave 2 either. The substrate's last prerequisite was the **SS-0 baseline**
(PR #2037) landing on trunk rather than a hosted publish — **met on 2026-07-17**.

| Gate item                        | Blocks the substrate? |
|----------------------------------|-----------------------|
| P-1 (at_chops 3.3.0 / `pqSeal`)  | No — already published (2026-06-23); substrate ungated |
| S-1 (`AtKeys`/`AtKeysIo` extend-in-place) | No |
| S-2 (`CryptoContext.keys`)       | No — sibling of the substrate on the critical path, not a prerequisite |
| S-3 (`LocalKeystoreAtKeysIo`)    | No |

**Merge discipline.** Per-package PRs to **trunk** in dependency order (no mega-PRs); rebase on trunk daily;
keep PRs small + additive / flag-gated so trunk stays releasable; prove cross-package combinations with an
**ephemeral** integration branch (or CI), not a standing one. **Interface-first** — freeze the `pqSeal`
signature (P-1), the extended `AtKeys`/`AtKeysIo` API (S-1), and the `CryptoContext.keys` field (S-2) first (stubs OK).
Integration is **continuous**, not a final step: each project merges to trunk when complete and publishes as
needed.

### (d) Testing harness pointer
`runLocal.sh` with `docker compose down` first, capped 180s; a test that mints `.atKeys` clears its own at
start and gitignores it; run **both** `tests/at_functional_test` and `tests/at_end2end_test` for any server
type/shape change (separate packages, invisible to at_client's own `dart test`/`analyze`). The detailed
per-UC harness and given/when/then live in [acceptance.md](../acceptance.md).

### (e) Conformance
Every PQ-touching PR — in **at_client_sdk** OR any **atServer implementation** — must cite a **project id**
from this plan (`P-1`, `P-2`, `P-3`, `S-*`, `SH-1`, `SS-*`, `KF-1`, `KE-1`, `B-*`, `R-*`, `RF-*`, `ON-1`,
`IS-1`, `D2-1`) **or** a
documented out-of-program status (e.g. "tracked in the NoPorts repo, out of this plan's lane"). Each PR must
also conform to the **current** [decisions.md](decisions.md) rulings: reviewers **reject** a PR that
implements a superseded ruling (e.g. the pre-decision-#F multi-key record, an `enroll:metadata` write path,
or the nested `apkam[]` roster). A PR whose design contradicts a live ruling is not merged until it is
re-scoped to the current shape or the ruling is formally changed in [decisions.md](decisions.md).

---

## 11. Coverage map (D1 package / UC → project)

Single authoritative map of D1 items, workstreams, and use cases to projects.

| D1 item / workstream / UC | Project(s) |
|---|---|
| D1-S S1 (at_chops stateless) | P-1 |
| D1-S S2/S3 (AtKeys/AtKeysIo extend-in-place, stores) | S-1, S-3 |
| D1-S S4 (WASM split) | S-5 |
| D1-S S5 (CryptoContext.keys) | S-2 |
| D1-S S6 (consumer bumps) | S-6 |
| D1-S keyfile-at-rest + backup/restore (new scope) | KF-1 |
| D1-A (PQ primitives, enrollment key) | P-1, P-2, P-3, KE-1 (the second KEM + `ver 0x03`) |
| D1-B B1-B4 (data path) | B-1, chunks B-1a…B-1e (+ key material SS-4) |
| D1-B B5/B6 (rotation/revocation) | B-2 |
| Key-establishment selectability + construction negotiation (`suites`) | KE-1 |
| D1-B B7 (selfEncryptionKey retirement) | B-3 (phases 1-3); phase 4 = the later ecosystem-gated release ([decisions 37](decisions.md#37-legacy-key-material-is-retained-until-the-ecosystem-is-pq-not-the-atsign-2026-08-05)), no longer R-2 |
| D1-C / D1-D (migration, flag, versioning) | R-1 (D1-D delivered; D1-C = the decisions-36 ladder + SH-1), R-2 |
| D1-F substrate baseline | SS-0 (PR #2037) |
| D1-F DEP1-DEP4 | SS-1b, SS-2, SS-3 |
| D1-F retrofit | RF-SRV, RF-2b, RF-2c (RF-1 confirm) — retirement via expiry + revoke (1:1:1; no per-key-delete project) |
| D1-E (at/pqmls shape) | D2-1 (D2) |
| UC-A1.1 PQ-native onboard + Decision #1 / UC-B4.2 | ON-1 |
| UC-A2.x / A3.x / A4.x / A5.x | SS-4, B-1, B-2, RF-2b |
| UC-A2.4 / A3.5 / A4.5 / A4.6 / A4.7 (KEM + construction selection) | KE-1 |
| UC-B0.x..B5.x | RF-2c (retrofit) + RF-SRV (critical path per decisions 40); B3/B4 data-path halves built |

See [acceptance.md](../acceptance.md) for the full UC catalogue; [decisions.md](decisions.md) records the D1-F
sub-item coverage rulings.

---

## 12. Open decisions pointer & verification provenance

The decision **rulings** are owned by [decisions.md](decisions.md). This is a pointer only, so the reader
knows where the sequencing assumptions come from:

- **#A** — `pqpublickey` interface freeze (P-3 vs SS-4): freeze the name + create-once contract before P-3
  starts; SS-4 owns the lifecycle.
- **#B** — `register()` call-site: **RESOLVED 2026-06-30** — the key package rides `enroll:request`
  as an opaque `EnrollParams.metadata`; no `enroll:metadata` verb. (Drives SS-1a/b/c + SS-2.)
- **#C** — keep D1 GA off the auth retrofit: B-2 depends on **RF-1 + SS-3**, not full RF-2.
- **#D** — publish-sequencing decisions: fold the pkam ML-DSA literal into SS-1a's publish; ML-DSA verify
  algo-level (P-2); re-confirm the at_commons floor at SS-1a; at_auth 3.1.1-vs-fold at S-1.
- **#E** — S-2 scope / the [section 3](#3-phase-a--pq-primitives--enrollment-key-p-1-p-2-p-3)-S5-vs-[section 7](#7-phase-rf--existing-client-retrofit-rf-1-rf-srv-rf-2b-rf-2c)-WP3 SoT conflict: this plan takes additive-field-only.
- **#F** — enrollment cardinality + retrofit shape: **RESOLVED 2026-06-30** — **1:1:1** + fresh-enrollment
  retrofit. (Drives SS-3 single-key, RF-SRV, and RF-2b/c.)

**Verification.** This plan is verified against the live trees: the `at_client_sdk` monorepo — which
**contains** `at_chops`, `at_auth`, and `at_commons` as workspace packages (`packages/at_chops`,
`packages/at_auth`, `packages/at_commons`) — plus the separate atServer implementation repos.

---

## 13. Phase IS — inter-server PQ authentication (IS-1)

*Off the D1 GA critical path (server-to-server, `at_server`), but in D1 scope (ruled 2026-07-06). This is
the atServer↔atServer handshake, orthogonal to the client-side `nskey` data path ([section 6](#6-phase-b--the-nskey-data-path-b-1-the-d1-centrepiece)) — a compromised
inter-server channel and a compromised client channel are different threats, so this track ships on its own
schedule and does **not** gate D1 GA.*

### IS-1 — atServer FROM/POL handshake: swap the challenge signature RSA → ML-DSA-65, RSA fallback · at_secondary_server · M

**Goal:** make the server-to-server FROM/POL handshake quantum-safe by swapping only the challenge
*signature* from RSA-2048 to ML-DSA-65, keeping the existing per-session UUID challenge (which already
provides freshness / anti-replay) and the TLS session (which already provides confidentiality). Automatic
fallback to legacy UUID/RSA for a peer that publishes no PQ signing key (zero flag day, mixed-fleet safe).
FROM/POL is authentication, not key agreement — so there is **no KEM**.

**Builds on:** the **published** at_chops 3.4.x only — `AtPqc.mlDsa65.signBytes`/`verifyBytes` (the P-2
ML-DSA-65 sign/verify branch) and `generateMlDsa65KeyPair`, both already shipped. **No unpublished at_chops
surface, no cross-package publish gate** — the earlier `XWingCert` / `resolveXWing` / `resolveMlDsa65`
requirement is dropped with the KEM.

**Deliverables:** (1) at boot, generate an ML-DSA-65 keypair (the signing keypair already needed) and
publish the public half as a protected `pq_signing_publickey@<atSign>` record — a **JSON object** for
crypto agility, initially `{ "ml-dsa-65": "<b64 pubkey>" }`, so a future algorithm is another field, not a
wire change. The ML-DSA secret key joins the protected-key set. (2) In A's outbound handshake, sign the
UUID challenge with ML-DSA instead of RSA — a one-line algorithm swap in the existing branch. (3) In B's
POL check, `lookup:pq_signing_publickey@<peer>` (live, never cached) → `AtPqc.mlDsa65.verifyBytes(...)`
instead of `RSAPublicKey.verifySHA256Signature(...)` — a one-line swap. Env `AT_DISABLE_PQ_AUTH=true` forces
UUID/RSA; self-auth always UUID; a peer publishing no PQ signing key falls back to UUID/RSA. **Explicitly
NOT built:** no certificate, no X-Wing encaps/decaps, no HKDF confirmation tag, no key expiry / rotation /
grace window, no `PqKeyManager` lifecycle class — a signing key needs no lifecycle state here (a change is a
re-publish, read live on the next handshake).

**Acceptance:** FROM/POL PQ path (ML-DSA sign → verify → `isPolAuthenticated`) + the RSA-fallback path;
`pq_signing_publickey` published as the agility JSON and looked up live; pure-Dart fallback (unset
`AT_CHOPS_LIBCRYPTO_PATH`, ML-DSA resolves to pure-Dart without throwing); mixed-fleet (a peer with no PQ
signing key → UUID challenge, POL via the RSA signing key). Existing delete/update verb tests still pass
(protected-key count updated for the ML-DSA secret key).

**Tracking:** PR **#2683** (`at_server`, `pq/st/pq-interserver-comms`) — **over-built against this scope;
to be pared back to the signature swap** (see [decisions.md](decisions.md), 2026-07-21). Off the D1 GA
critical path. Sub-issue [#2049](https://github.com/atsign-foundation/at_client_sdk/issues/2049) under
#1889. Design detail in [design.md](../design.md) (§8 inter-server PQ authentication).

**Watch-outs:** `pq_signing_publickey` is looked up live every handshake and never cached — keep it that
way, so a re-published key takes effect on the next handshake with no rotation machinery. Do not
re-introduce a KEM, cert, or tag: the UUID challenge the swapped signature covers is the entire freshness
mechanism, and the TLS session already secures the channel.

---

## 14. Backlog — carried items with no owning project

Small, real, and homeless: none is big enough to be a project, and each would
otherwise live only inside a `decisions.md` section nobody greps. Ruled in
[decisions 46](decisions.md#46-rfc-9180-and-where-the-designs-version-hatches-are-2026-08-05)
and revisited in
[decisions 48](decisions.md#48-the-standards-question-reopened-and-what-the-check-found-2026-08-06);
tracked here so they are visible from the plan.

**One deadline is live, and it is prospective rather than a date.**
[14.22](#1422-making-the-signing-root-rotatable--decisions-101) is a *reader*
change, and no client in the field reads the signing root today — nothing is
released. The deadline is the GA minor: once it ships readers that take the
first entry of the root's `keys[]`, those are what would stop a second entry
ever being adopted. That is the reason the work is in D1 rather than after it.

The three this paragraph used to name have all passed, which is worth stating
rather than deleting — each is a shape now frozen. **14.1** froze when ON-1 made
every activated atSign keep its root, and was ruled the same day. **14.3** was
settled, so the wrapper shape 14.6 depended on is fixed. **14.6**'s own deadline
was retired deliberately: `enroll:update` makes the enrollment record rewritable
by its owner, so what remains there is a caller, not a freeze.

The rest are cheap while at_java has no PQ code and expensive afterwards, which
as of 2026-08-06 has not started.

**Nine are closed** — 14.2, 14.4 and 14.5, all absorbed by **KE-1**
([decisions 50](decisions.md#50-two-kems-by-configuration-one-construction-by-negotiation-2026-08-07));
**14.1**, ruled by **ON-1**
([decisions 52](decisions.md#52-on-1-a-greenfield-atsign-starts-where-a-retrofit-ends-2026-08-08));
**14.3**, ruled 2026-08-06, landed 2026-08-09 and since superseded into a single
envelope shape; **14.9** with **14.9a**, root-caused as an `EnrollmentManager`
cache race and fixed in at_server `16dd457f`; **14.10**, resolved by a
release-pinned pre-PQ image; **14.13**, folded into the rollout axis; and
**14.21**, ruled the day it was raised by
[decisions 101](decisions.md#101-the-signing-root-becomes-an-ordinary-signing-key-and-rotatable-2026-08-15),
with its work carried by 14.22.
They are kept here rather than deleted because each names a hatch the wire now
depends on, and a reader asking "why can the construction change without a flag
day" needs to find the answer where the question was recorded.

**Twelve are live:** 14.6 (both halves built; a caller that re-advertises a
key package is owed), 14.7, 14.11, 14.12, 14.14, 14.15, 14.16, 14.17,
14.18, 14.19, 14.20 and 14.22. ⚠️ **14.8 left this list 2026-08-15** when step
27 landed; 14.22 is complete but is kept here because its section carries the
detail of what it built.

⚠️ **Re-derived 2026-08-15 by reading each subsection's own state marker**, and
all three of this paragraph's claims were wrong: it counted four done rather
than eight, it listed **14.3** as live when 14.3's own heading has said DONE
since 2026-08-09, and its range stopped at 14.11 — written before 14.12 existed
and never revisited across nine further items. A list of current state is worth
exactly its last re-derivation date, which is why this one now carries one.

### 14.1 The signing root's `keys[]` shape — DEADLINE: the first root we keep

> ⛔ **SUPERSEDED 2026-08-15 by [decisions 101](decisions.md#101-the-signing-root-becomes-an-ordinary-signing-key-and-rotatable-2026-08-15)
> and [14.22](#1422-making-the-signing-root-rotatable--decisions-101) — read
> those before acting on anything below.** This item is kept for the reasoning
> that produced its ruling, and two of its conclusions are now **false**: the
> bare-base64 reader is **deleted** rather than kept, and the shape is **not**
> permanent — the record becomes mutable behind a mint lock. The premise both
> rested on ("roots already published can never be rewritten") was the
> greenfield rule re-litigated in a new costume: nothing is released, so every
> atSign holding a root is ours. Its line references (`:208-211`, `:108`) are
> also stale; the code is at `:248-259` and `:139-149`.
>
> **RULED 2026-08-08 — tagged. Closed.** ON-1 was the state this deadline named — every atSign activated from
here keeps a root — and ON-1's live test walked straight into it. The **tagged**
> form won: `pq_signing_root.dart` now publishes
> `[{"alg":"ml-dsa-65","pub":"<base64>"}]`, so the code moved and both documents
> stood. The reader still accepts bare base64, because roots already published
> in that form can never be rewritten. See
> [decisions 52](decisions.md#52-on-1-a-greenfield-atsign-starts-where-a-retrofit-ends-2026-08-08).
> The rest of this item is the reasoning that produced the ruling, kept because
> it is the record of why the shape is permanent.

The code and the catalogue disagreed about the shape of the one record in the
system that can never be rewritten.

| | shape |
|---|---|
| Published + parsed by `pq_signing_root.dart` (`:208-211`, `:108`) | `{"v":1,"keys":["<base64>"],"successor":null}` |
| Documented by [acceptance.md](../acceptance.md) and [decisions 46.5](decisions.md#465-the-signing-root-is-the-only-one-way-door) | `keys: [{"alg":"ml-dsa-65","pub":"<base64>"}]` |

`public:pq_signing_root@<atSign>` is an **immutable create-once** record that
never rotates ([decisions 18](decisions.md#18-pqpublickey-becomes-the-user-owned-signing-root-2026-08-03)).
The `v` field lets a later reader *detect* a v1 root; it does not let anyone
*replace* one. `successor` is the only migration path and is unimplemented.

So the deadline is a **state, not a date**: every root published so far lives on
a recycled virtualenv and is disposable, and the shape becomes permanent the
first time a root lands on an atSign we do not recycle — a developer's own
atSign, a pilot, anything long-lived. After that, whichever form is chosen the
other one is wrong forever on those atSigns.

Deciding needs no code and takes minutes; **do it before the next long-lived
atSign runs a privileged PQ client**, not before a release. The bare-base64
form is what ships and is smaller; the structured form is what every other key
structure here uses (`_apsk`'s array, the key package) and is the only one that
can carry a second algorithm. Whichever wins, the loser's document changes in
the same commit as the decision.

### 14.2 A version on the two signed payloads — DONE

Landed in `3c2eddbe6`: the signed-envelope wrapper and the nskey advertisement
payload both carry a version field. Both records ARE rewritable, so this was
cheap insurance rather than a deadline — but it is the hatch that makes 14.3
reversible, which is why it went first of the three.

### 14.3 JWS or JCS for the signed envelope — DONE (one shape, no flag)

**RULED 2026-08-06 → JWS, `b64=true`**
([decisions 48.8](decisions.md#488-what-this-entry-does-not-rule)); the
*Flattened* serialization it named became *general* under ruling 95.1 below,
so the array can gain a signature rather than the shape having to change.
**LANDED 2026-08-09** ([decisions 60](decisions.md#60-jws-stage-one-lands-readers-always-on-producer-behind-the-version-flag-2026-08-09))
as a second shape beside the tagged one, behind a version flag —
**superseded 2026-08-12** by
[`decisions.md` 95](decisions.md#95-the-envelope-keeps-one-shape-and-a-retained-key-says-so-2026-08-12)
ruling 1, which deleted both earlier shapes and the flag: the envelope is RFC
7515 **general** serialization and nothing else, with `alg`, `kid` and `v` all
inside the protected header — joined by `typ` on 2026-08-15
([`decisions.md` 103](decisions.md#103-an-envelope-says-what-it-is-for-and-a-verifier-says-what-it-wants-2026-08-15)). Adjudicated by two third-party verifiers
(jose for RS256, OpenSSL 3.6 for ML-DSA-65 — decisions 60.4), with committed
vectors at `packages/at_client/test/vectors/jws_envelope.json`. Its
prerequisite 14.2 landed in `3c2eddbe6`; the staged plan it was executed from
is `untracked/2026-08-06-JWS-MIGRATION-PLAN.md`.

Why it became the cheapest standards adoption in the design rather than the
most marginal: RFC 9964 (Proposed Standard, May 2026) registers `ML-DSA-65` as
an IANA JOSE `alg`, our ML-DSA is already conformant to it (pure, empty
context, now pinned by test), and the RSA arm already emits exactly the
`RS256` bytes. Adopting it re-labels a container around cryptography that
already conforms. It also signs `alg` and `enrollmentId`, which sit outside
the signature today.

JCS is rejected: there is no RFC 8785 package on pub.dev, so it means
hand-writing an ECMAScript-number-formatting canonicaliser — the exact risk we
are removing. `canonical_json` on pub.dev is a trap, being OLPC Canonical JSON
under a Google publisher badge. `b64=false` is rejected too: it does not
deliver the `llookup` readability that is its only appeal, and its mandatory
`crit` forfeits off-the-shelf verification.

One measured trap worth carrying here rather than only in the plan, since it
inverts the obvious expectation: Dart's `base64Decode` requires padding and JWS
base64url is unpadded, so a **256-byte RSA-2048 signature (342 chars, len%4=2)
always throws** while a **3309-byte ML-DSA-65 signature (4412 chars, len%4=0)
always decodes**. A naive migration therefore fails on every classical envelope
and succeeds on every PQ one. Use `base64Url.decode(base64.normalize(s))`.

### 14.4 A `suites` list on the key package — DONE

Landed in `1688ed69d`, corrected in `c9f8580da`, and given its first production
reader in `827e2526d` (all **KE-1**). It is what makes the construction a
sender-side decision rather than a fleet-wide readers-upgrade-first migration,
so `ver = 0x02` now goes to a peer that says it can open it and `0x01` to one
whose package predates the field. The same mechanism was then given to the
nskey advertisement in `f3e5b3686`, which is what let the conveyance path move
too.

The correction is the part worth keeping: the field defaulted to
`SecretSharingAlgos.suites`, so widening that list made every package claim a
construction its key cannot decapsulate. A published list must be derived from
the **keys** a package advertises, never from what the build supports — see
[decisions 50.5](decisions.md#505-the-defect-a-widened-list-planted-before-anything-read-it).

### 14.5 A write-side envelope version selector in at_chops — DONE

Landed in `1688ed69d`: `pqSeal` takes a `version`, and `pqSealDefaultVersion` /
`pqSealSupportedVersions` are public. It was the blocker on the RFC 9180 move,
which landed at `f3cfda4d4` as `ver = 0x02`
([decisions 48.9](decisions.md#489-rfc-9180-landed-and-what-it-settled)).

### 14.6 The enrollment record's `metadata.keyPackage` is a one-way door

**Status: BUILT on both sides, 2026-08-13. The door opens, and it has a handle each side.** ⚠️ This read `PARTLY BUILT 2026-08-11` until 2026-08-18, while the row sat in **DONE** — the inverse of the drift that left 14.17 in TODO, and survivable only because the remaining half is tracked under **KE-2** in PARKED, where nobody reading DONE would look. What this item owed is built; what remains is a *consumer*, and that is KE-2's scope, not this one's. `enroll:update` ([`decisions.md` 91](decisions.md#91-signature-agility-the-apkam-auth-key-stops-being-the-enrollments-signing-key-2026-08-11)
ruling 13, superseding `enroll:updateMetadata` in
[`decisions.md` 68](decisions.md#68-the-enrollment-record-stops-being-a-one-way-door-enrollupdatemetadata-2026-08-10))
reaches `metadata` — along with `apkamPublicKey`, `signingAlgo` and `apsk` —
and is **built and functionally verified on the atServer** (at_server
`gkc-apsk-auto-publish`, 210/210). ✅ **The client caller landed 2026-08-13**
([14.18 step 16](#1418-the-remaining-d1-initial-development-sequence)), so the
door has a handle on both sides: `EnrollmentUpdateRequest.metadata` merges
per-key into the record, and the remedy for an unparseable key package is no
longer delete-and-re-enrol. What is still owed is a *caller that uses it for
that* — nothing re-advertises a key package today. The original statement of
the defect follows.


It is a signed envelope, and it is written only by `enroll:request` and never
afterwards — `enroll_verb_handler.dart` persists `enrollParams.metadata` in the
new-enrollment branch alone. A reader that cannot parse a frozen wrapper
returns `KeyPackageStatus.unsupported`, and that enrollment can then never
receive a sealed conveyance; the only remedy is to delete and re-enrol the
device.

So it belongs on the one-way-door list beside the signing root
([14.1](#141-the-signing-roots-keys-shape--deadline-the-first-root-we-keep)),
and 14.3's wrapper shape has to be settled before enrolments that matter are
created. [decisions 46](decisions.md#46-rfc-9180-and-where-the-designs-version-hatches-are-2026-08-05)
does not list it.

**Ruled 2026-08-10 — the door gets a handle, and the deadline goes with it**
([decisions 68](decisions.md#68-the-enrollment-record-stops-being-a-one-way-door-enrollupdatemetadata-2026-08-10)).
`enroll:update` makes the record rewritable by the enrollment that owns
it, so 14.3's wrapper shape stops being an irreversible bet and the remedy for an
unparseable package stops being delete-and-re-enrol. It was unbuilt when this was
written — both halves now exist (see the status above), so what remains is a
caller that re-advertises a package, not a shape-freezing deadline.

### 14.7 NoPorts carries its own copy of the envelope shape

⛔ **NOT D1 (gkc, 2026-08-23), and moved to `## PARKED`.** This section's own
text says a migration here does not break NoPorts. Its obligation is
conditional and has not fired: naming NoPorts as a second migration is owed
when **RFC 7515 becomes a consumer-facing claim**, and measured 2026-08-22 that
string appears in `design.md` and `detail/decisions.md` and in no file under
`packages/`.

`sshnoports/packages/dart/noports_core/lib/src/common/validation_utils.dart`
produces the same `{payload, signature, hashingAlgo, signingAlgo}` shape with
the same re-encoding behaviour. It does not import at_client's functions — it
signs with the encryption keypair and fetches `getRemotePK` rather than
`_apsk` — so a migration here does not break it. But "nobody has this shape
deployed" is wrong, and if the pitch becomes "our envelopes are RFC 7515" then
NoPorts is a separately-owned second migration to name rather than discover.

### 14.8 Domain separation on the signed envelope

The `from:` challenge and a to-be-signed envelope are both signed by the
enrollment's signing key, so their shapes must stay disjoint
([decisions 51](decisions.md#51-the-from-challenge-and-a-signed-envelope-must-never-share-a-shape-2026-08-08)).
They are today, and `at_lookup` 3.6.1 asserts the challenge half. Domain
separating the envelope makes it true by construction rather than by coincidence
of two formats.

Belongs on the PQ branch, not trunk: it changes the signed bytes.

⚠️ **Updated 2026-08-12.** The original reason — a dispatch on
`signedEnvelopeVersion`, and compatibility with envelopes written by a released
build — is void: `signedEnvelopeVersion` is deleted by
[`decisions.md` 95](decisions.md#95-the-envelope-keeps-one-shape-and-a-retained-key-says-so-2026-08-12)
ruling 1, and nothing released writes an envelope. Nothing external constrains
this now; it lands with the one-shape work.

✅ **DONE 2026-08-15 —
[`decisions.md` 103](decisions.md#103-an-envelope-says-what-it-is-for-and-a-verifier-says-what-it-wants-2026-08-15).**
Per-use `EnvelopeType` in the protected header, `expecting` on both verify
entry points, `at-root-link:` on the root link's signed bytes, and
`publishOwnRootLink` re-anchoring a link that no longer holds — without which
changing those bytes would have stranded every root link already published.

⚠️ **The row understated its own scope, the eighth time on this branch.** It
named the `from:` challenge; the reachable confusion was between the envelope's
**five** production uses, which a signature could be moved between freely
because nothing said what a document was signed *as*. Read 103.2 before citing
this section for what step 27 was about.

### 14.9 A revoked enrollment can still authenticate, briefly

> **ROOT-CAUSED 2026-08-12 — it WAS an atServer defect.** `EnrollmentManager`
> invalidated its read-through `atDataCache` **before** writing the record:
> `put` did `remove(ek)` → `await movePerEnrollmentData(...)` (a whole-keystore
> walk, many suspension points) → `await keyStore.put(...)`. Any other
> connection reaching `getEnrollmentByFullKey` inside that window missed, read
> the **pre-revoke** record, and re-cached `approved` — permanently, because
> nothing invalidated after the write. That cache is read on every verb
> command and by `PkamVerbHandler.verifyEnrollmentIsActive`, so the revoked
> enrollment kept authenticating. `remove()` had the same shape. Fixed in
> at_server `16dd457f`: both mutate first, invalidate second, with no `await`
> between the write landing and the eviction. 12 of 12 clean full-suite runs
> after, against 5 failures in 13 before — a rate, not a proof of kind.
>
> **The 2026-08-11 ruling below closed this as "a test-instrument failure,
> proven. Not an atServer defect, and nobody should go looking for one"
> ([`decisions.md` 93](decisions.md#93-the-d1-remaining-work-sequence-and-the-rollout-axis-becomes-real-2026-08-11)
> ruling 5). That conclusion did not follow from its evidence.** The test it
> cited is serial — one client, no competing reader — so it never opens the
> window, and a passing serial test cannot exclude a concurrency race. The
> harness faults it found were real and worth fixing; fixing the instrument
> does not establish that the instrument was the cause. The tell was in the
> data and was read as noise: the row failed only inside the **full suite**,
> never standalone and never paired. "Passes alone, fails in the suite" was
> attributed to leftover state; it was concurrency, which is the other thing
> that phrase means.
>
> The text below is the original observation, kept as history.

Observed 2026-08-07: a fresh connection PKAM-authenticated with a revoked
enrollment's own keypair after `enrollmentService.revoke()` had returned, once
in three consecutive full-suite runs. atServer-side — the PKAM path appears to
resolve enrollment state through the same cache `enroll:listns` is served from,
and the roster half of the same test already polls around that staleness.

Matters because revocation is the enforcement that `excludeEnrollmentIds` is
only a courtesy for. The client-side assertion is now bounded (`d6fe103ba`), so
the suite still fails if the credential never stops working — that is a test
fix, not a fix for the lag. Next step is `pkam_verb_handler` / the enrollment
cache in at_server. Sits beside the RF-SRV cascade residual
([decisions 42](decisions.md#42-the-to-define-list-ruled-2026-08-05) item 2).

**Worse, 2026-08-08, and still intermittent.** Five full-suite runs in one
session: the revoked credential kept authenticating past the client's
**10-second** bound (20 polls × 500ms) on **four of them**. So the rate moved
sharply — 2026-08-07 saw one failure in three, this session saw four in five —
without the behaviour changing kind. It is not a
regression from anything in this repo: the suite was run with that session's new
test file removed and with it restored, in the same session, and both arms
failed identically at the same point.

Two consequences worth stating. A green functional run does **not** mean this is
fixed, so do not read one as evidence either way. And the 10s bound is now the
thing that decides pass or fail, which makes the rail's colour a measure of the
atServer's cache latency rather than of the client — the argument for fixing
`pkam_verb_handler` rather than raising the bound again.

### 14.9a The attribution above was never established — the test was

**Everything before this heading is retained as the record of what was
believed, and it should not be relied on.** Challenged 2026-08-08 by Gary
("something is wrong about the test"), the instrument was examined instead of
the atServer, and it did not support the conclusion.

The revoke **is** properly awaited — every hop from the test through
`EnrollmentServiceImpl.revoke`, at_auth, `AtLookupImpl._process` and the socket
read, with no fire-and-forget anywhere, and an `error:` response would throw out
of the call. That much of the original story survives. But:

1. **The test discarded the acknowledgement.** `revoke()` returns an
   `AtEnrollmentResponse` carrying the enrollment id and status, and nothing in
   this tree ever checks it — not this test, not `enrollment_teardown.dart`,
   not `nskey_rotation.dart`, not the CLI. A `data:` response whose status is
   anything other than `revoked` was silently accepted. So "the credential
   still works" was **equally explained by the revoke not having taken**, and
   choosing the cache explanation over that one was a guess.
2. **The revoked enrollment's own client was never stopped.** It held a live,
   authenticated connection carrying that enrollment id for the whole 10-second
   poll — while the posited mechanism is an atServer-side enrollment cache. The
   test may have been holding open the very thing it waited to see expire. It
   is not what the scenario describes either: the lost-laptop case is a keyfile
   in someone else's hands, not a session still running.

Both are fixed. The test now asserts the ack names this enrollment and reports
`EnrollmentStatus.revoked`, and stops the doomed client before polling — after
which the **full functional suite went green (143/143), first clean run in a
session where it had failed four times in five.** One run is not proof and the
rate above says why, but the atServer-lag attribution no longer has evidence
behind it and should be treated as open rather than as a known server defect.
Re-derive it from a run of the fixed test before spending anything on
`pkam_verb_handler`.

**The general lesson, which is why this is written up rather than quietly
edited:** a test that throws away a response cannot distinguish "the thing did
not happen" from "the thing happened and is not visible yet" — and the second
is the more interesting story, so that is the one that gets written down. Assert
the acknowledgement.

⚠️ **Superseded 2026-08-12 — read 14.9's opening blockquote, not this.** "Treat
it as open rather than as a known server defect" was right on the evidence
available on 2026-08-08 and is wrong now: the race was found in
`EnrollmentManager` and fixed in at_server `16dd457f`. This section stays as the
record of a correct challenge to a wrong attribution; it is no longer the
current state.

### 14.10 UC-B0.1 needed a legacy atServer image — RESOLVED 2026-08-08

It needed an atServer **without** the retrofit verbs to abort cleanly against,
and no image in this repo provided one, so it was parked as "re-scope or waive".
`atsigncompany/virtualenv:vip-p3.15.0` resolves it: a release-pinned tag stays
pre-PQ for good, where `vip` gains post-quantum support and stops being a legacy
atServer. The row is proven against the pin — see
[acceptance.md UC-B0.1](../acceptance.md#uc-b01--a-pq-capable-client-cannot-pq-upgrade-against-a-legacy-atserver)
— and the acceptance suite was **45 of 45** at that date (it has since grown; the live count is pinned by `packages/at_client/test/acceptance/README.md` and its guard).

Two things worth keeping. The row had carried `blocked: RF-SRV` for three days
after RF-SRV's server half landed, because a blocker naming a *project* goes on
being cited long after the project ships; what actually blocked it was the
harness. And writing it found a real defect rather than merely ticking a box —
the aborted upgrade left its own enrollment request `pending`, one per retry.

### 14.11 `deprecated_member_use` findings across the workspace

Everything else `dart analyze` reported is cleared (`3e3ac1075`); at_chops and
at_commons are clean outright. What remains is live use of
deprecated-but-still-required APIs — the `AtChops` compatibility shim,
`AtSigningInput`, `apkamPublicKey` — so clearing them means migrating call
sites, which is a code change rather than a lint sweep and wants its own pass.

**Re-measured 2026-08-13** (the heading said 299 and named only at_client). Per
package, `dart analyze lib test` from each package directory, counted with
`grep -c deprecated_member_use`:

| package | findings |
|---|---|
| `at_client` | 340 *(2026-08-13 snapshot; 396 as of 2026-08-23 — see the live plan's 14.11)* |
| `at_onboarding_cli` | 183 |
| `at_auth` | 110 |
| `at_lookup` | 28 |
| `at_chops`, `at_commons` | 0 |

⚠️ **Scope this before starting it — a straight "migrate off the deprecated
member" sweep is not available for the PKAM signing path.** `PkamSigningAlgo`
and `PkamMlDsa65SigningAlgo` are both deprecated *classes*, and so are
`AtChopsImpl`, `AtChopsKeys`, `AtSigningInput`, `AtSigningMode` and
`AtPkamKeyPair`. Non-deprecated key material *does* exist —
`RsaSignatureAlgo`, and `MlDsa65PureDartAlgo.signBytesSync`/`verifyBytes` with
explicit keys — so what is missing is not a replacement but the **dispatcher**:
nothing non-deprecated selects an algorithm from a `SigningAlgoType` the way
`AtChopsImpl.sign` does in pkam mode. A caller wanting both algorithms writes
the two-way branch itself.

And the RSA arm is not a free swap: the atServer's `ApkamSignatureVerifier`
records that **`RsaSignatureAlgo` refuses any modulus that is not exactly 2048
bits, which `PkamSigningAlgo` does not**, so adopting it would stop an
enrollment holding an off-size RSA key from authenticating. That is a change to
what verifies on the authentication path, not a refactor. Any sweep that
touches signing has to decide this deliberately; the rest of the findings
(models, `apkamPublicKey`, collection APIs) are ordinary migrations.

### 14.12 A `mintLegacyMaterial:false` atSign cannot write a public record

Found 2026-08-08 by UC-B4.2's opt-out arm, the first thing ever to activate an
atSign that way and then use it. The opt-out works exactly as designed at
activation — no RSA keypair is minted, no `public:publickey` is published, and
`completeActivation` says so — but the resulting atSign cannot then publish
anything, because **every public write is signed with the legacy encryption
private key**
(`put_request_transformer.dart` `_signPublicData` throws
`AtPrivateKeyNotFoundException('Failed to sign the public data')` when it is
absent). Two things the post-quantum path itself needs are public writes: the
enrollment's `_apsk` anchor to the signing root, and the nskey advertisement.
Both fail, live and logged, on an opt-out atSign. Sync fails alongside them —
"Self encryption key is not set for current atSign" — because there is no
`selfEncryptionKey` either.

So `mintLegacyMaterial: false` is a switch that exists and is honoured but is
**not yet a usable configuration**, which matters because
[decisions 42](decisions.md#42-the-to-define-list-ruled-2026-08-05) item 10 has
the release default resolving null→false in the major after R-2. Closing it means public-record signing moves onto the
ML-DSA signing root rather than the RSA encryption keypair — the same swap
IS-1 made for inter-server auth — and self data moves off `selfEncryptionKey`
onto the nskey path (B-3 phase 1). Neither is scheduled here; the point of this
entry is that the stop-release cannot ship before both are, and that the
`mintLegacyMaterial` flag must not be recommended to anyone until then.

Asserted, rather than merely noted, in the opt-out arm of
`tests/at_functional_test/test/pq_legacy_interop_live_test.dart`: it expects the
public write to fail with that exact reason, so whichever project fixes this
gets a red test naming the row that was waiting for it.

### 14.13 A passive-by-default flag: surveyed, not built

> **FOLDED AWAY 2026-08-11 — this is no longer a separate item.**
> [`decisions.md` 93](decisions.md#93-the-d1-remaining-work-sequence-and-the-rollout-axis-becomes-real-2026-08-11)
> ruling 1 makes `now|rollout1|rollout2` a new axis on `PqPosture`, and
> **passive-by-default is precisely what the `now` position means**. Build the
> axis ([14.18](#1418-the-remaining-d1-initial-development-sequence) step 19)
> and this is delivered with it. Kept for the survey below, which is the list
> of what today writes on its own initiative — that list is what the `now`
> position has to switch off, so it is still the working material.

The branch's default behaviour should be **passive** — a client built with a
default `AtClientPreference` should read and route post-quantum records but
never write one on its own initiative. Today it does write: `_apsk` publishes,
`__ssenv` envelopes and their notifications, envelope deletes, and two kinds of
`_apsk` `appMetadata` rewrite, on every client start.

**This is NOT required to protect the cicd atServers** — that is done, by
segregating the PQ e2e tests ([14.15](#1415-pre-pr-rails-checklist)). It was
established empirically that no non-PQ e2e test writes PQ material: every active
write is downstream of the client holding an `AtKeysIo`, and the e2e harness
builds ordinary clients through `setCurrentAtSign` without one, so they log
*"Not sweeping chain links: this client has no registered key package to seal
conveyances from"* and do nothing. The flag is a **merge property** — it makes
the branch inert for every existing consumer — not a pollution fix.

The survey, so it is not repeated. Everything active hangs off
`AtClientImpl._fileConveyedKeysAndAnchor()` (ungated) and `_seedNamespaceKeys()`
(already gated by `seedNamespaceKeys`, default false). Do **not** gate the whole
of the former: two of its steps are preconditions for *reads*, and gating them
breaks decryption rather than quietening writes —
- the `collectConveyedKeyMaterial` sweep is the only route by which a conveyed
  nskey private reaches the keyfile, and
- `bindKeyPackageToAtKeys` (one production call site, inside it) is what stops
  the client minting a fresh enc keypair per process and advertising a `kpid`
  its enrollment record does not name.

Gate instead at the individual call sites — the signing-root request, the
missing-private requests, both chain-link publishes, the unanchored sweep, the
`publishPublicSigningKey` inside `register()`, the read-path
`_askForMissingPrivate` conveyance hook — and leave `_adoptEraCryptoDefault()`
alone, which writes nothing. Approve-side conveyance is *reactive* (it fires
only because an enrollee advertised a key package) and should stay: refusing
would approve a device that can decrypt nothing. Explicitly-invoked entry points
(`pqNativeOnboard`, `selfRetrofit`, `mintSigningRootAfterActivation`) are the
opt-in and need no gate.

Blast radius if it lands: the live packs' two shared preference helpers plus one
inline `AtOnboardingPreference` cover every test that needs it on. Watch for the
two tests that would go **vacuously green** rather than red — the absence arms
of `signing_root_pull_two_enrollments_test` and `nskey_rotation_live_test`.

### 14.14 A client with no enrollment id is treated as fully privileged

`EnrollmentRecordPrivilegeResolver.isFullyPrivileged()`
(`service/enrollment_privilege_resolver.dart`) returns **true unconditionally
when `enrollmentId == null`**. ⚠️ Its own dartdoc now argues the case this item
frames as open — *"full privilege by construction rather than by grant."* The
behaviour is unchanged; the name moved verbatim on 2026-08-10 (`289bbe453`),
and this cited the old one until 2026-08-18. Also, and `ApkamSigning.enrollmentId` substitutes the
sentinel `'primary'` when there is none. So a legacy PKAM client that happens to
hold an `AtKeysIo` publishes `public:_apsk.primary.a.__e@<atSign>` and signs
approval-chain links as `"primary"`.

Found while surveying for [14.13](#1413-a-passive-by-default-flag-surveyed-not-built),
and worth separating from it: a flag would *hide* this rather than resolve it.
The question is whether an owner-keys client should be in the enrollment trust
chain at all, and if so under what identity — `'primary'` is a name no
enrollment record carries.

### 14.15 Pre-PR rails checklist

✅ **NOTHING OWED, since 2026-08-10.** The single item is struck below. What
remains is the external gate — the published atServer image verifying ML-DSA
PKAM — and that is **step 32's blocker**, not a checklist entry. ⚠️ This section
sat in the TODO table until 2026-08-18 because its opening read as a condition
rather than a status, which also put the done marker outside the window the new
TODO-row guard reads.

No PR opens against this branch until the published atServer image verifies
ML-DSA PKAM (owner's call, 2026-08-08). The one thing that had to be true by
then:

> ~~The functional pack's compose hardcodes a local image, so CI's
> `docker compose pull` kills the job~~ — **done, verified 2026-08-10.** All
> three packs now commit `image: ${VIRTUALENV_IMAGE:-atsigncompany/virtualenv:vip}`
> (functional `docker-compose.yaml:13`, e2e `:14`), and each `runLocal.sh`
> exports `VIRTUALENV_IMAGE="${VIRTUALENV_IMAGE:-at_virtual_env:local}"` and
> skips `docker compose pull` for a name containing no `/`. A clean checkout
> and CI therefore resolve the published image with no environment set, while
> our runs opt into the local build. **Nothing needs reverting before a PR.**

1. **The `pqe2e_tests` CI job is written but UNVERIFIED.** Nothing has run it
   end to end, because no published image supports the tests it runs. Run it
   once the image lands, before trusting it. An image without PQ support fails
   at authentication with a server-side
   `AT0010-Exception: RangeError (length): Invalid value: Not in inclusive range 0..47: 48`
   from `AtLookupImpl.pkamAuthenticate` — that signature means the image, not
   the client.


### 14.16 Four residuals the issue-tree audit surfaced, 2026-08-09

⛔ **STEP 29 LEAVES D1 — all four residuals dispositioned 2026-08-23.** ① the
perf ceiling goes to a post-D1 cleanup (#2153); ② UC-A3.4 landed 2026-08-17;
③ the SS-4 resume question is RULED — no resume — and re-filed as orphan
growth; ④ the IS-1 drift is not D1, on a separate track in at_server. Each is
recorded against its own item below.

Updating the #1889 tree to the current state meant auditing every open issue's
own deliverables against the code rather than against the plan. Four things were
owed that no ledger recorded — and two plan claims were wrong, now corrected in
place (the layer-3 AAD literal, and UC-A3.4 below).

1. **The performance ceiling is not pinned.** [acceptance.md](../acceptance.md)
   asks for the deltas measured on *one reference low-end device*, with the
   ceiling pinned when the harness lands. The harness exists and has been run —
   but only on a 16-core arm64 Mac, which is the opposite of the device the
   criterion names. Until it is re-run, "performance is measured, not assumed"
   is not yet true. ⚠️ **This ended "B-1's own unmet acceptance requirement
   (#2010)" until 2026-08-18, and #2010 is CLOSED** — its closing note splits
   the requirement out to
   [#2153](https://github.com/atsign-foundation/at_client_sdk/issues/2153),
   which is open and is now this residual's only home; it appeared nowhere else
   in this plan.
   ⚠️ **And the harness did not build for six days.** `26705b6a0` (2026-08-12)
   made `pqSeal`/`pqOpen`'s `info` required without updating
   `benchmark/crypto_bench.dart`, leaving five `missing_required_argument`
   errors. Nothing local caught it: the package's routine command is
   `dart analyze lib test`, which never looks in `benchmark/`. CI's at_client
   job runs a **bare** `dart analyze` from that same directory, which does — so
   this would have failed the first PR carved out of this branch. It has not
   failed one yet, because CI has never run on `gkc-pq-d1-spike` at all
   (`gh run list --branch` returns zero rows against a control that returns
   rows). Fixed 2026-08-18: the five call sites pass a binding of the shape
   production seals under, and the bench builds, runs and passes the format
   gate. A harness that does not compile is a stronger version of the finding
   this residual already records — the budget was not merely measured on the
   wrong device, it could not be measured at all.
2. ✅ **UC-A3.4's self direction is live, DONE 2026-08-17.** It had been
   unit-only — both live notify tests were alice→bob and the alice1→alice2 case
   was asserted against a `MockAtClient`, while the plan claimed both A3.4 and
   A4.4 were live-covered. `nskey_self_notify_live_test.dart` now drives it
   against a live atServer: two real enrollments of one atSign, the nskey
   minted before either existed, the treaty delivered to the second
   enrollment's monitor and decrypted with the private conveyed at approval.
   Two product fixes were needed and both landed with it — the content-key
   conveyance retries **remotely** when the local read misses (only the self
   direction can hit that; a cross-atSign conveyance is owned by the other
   atSign with no `ttr`, so it was always a remote lookup), and the
   notification dispatch loop awaits its transforms instead of discarding them
   via `Map.forEach`. What the row does **not** cover is a notification that
   outruns its key — ⚠️ **which is no longer dropped**: 14.30 shipped the park
   and re-drive
   ([decisions 106.5](decisions.md#106-a-notification-that-outruns-its-key-is-dropped-not-parked-2026-08-16),
   [14.30](#1430-a-content-notification-can-outrun-the-key-that-opens-it)),
   and this line said "still dropped" until 2026-08-18. It is held until the
   generation it needs is filed, bounded by `maxParked`/`parkTtl` with every
   eviction logged at `warning`.
3. **SS-4: the *nskey* mint does not resume an interrupted mint. The signing
   root's does.** ⚠️ This said "an interrupted mint does not resume" of SS-4 as
   a whole until 2026-08-18; SS-4 covers two mints and they differ. The
   **signing-root** mint resumes: `pq_signing_root.dart:392` reads the keyfile
   and, where a crash left a pair filed but unpublished, finishes the publish
   with that pair instead of generating a new one — "The crash between filing
   and publishing: finish the publish with the pair already filed". That landed
   in `7e62e613a` on 2026-08-05, **four days before this residual was written**,
   which is why the general form was wrong on the day it was recorded. The
   **nskey** mint does not: `_mint` always generates a fresh seed
   (`published_nskey_key_ring.dart:559`, `NskeySeed(kem.newSeed())`) and never
   reads back a filed-but-unpublished pair — and because it files the private
   *before* publishing the advertisement by design (`:574`, "Durable BEFORE the
   advertisement goes out"), a crash in exactly that window orphans the filed
   private. Still worth deciding whether resume is required there rather than
   assuming it: the mint lock and the election
   ([decisions 105](decisions.md#105-the-nskey-mint-elects-a-winner-2026-08-16))
   have both landed since, and may make re-generation safe (#2087).
4. **IS-1's record name drifted from its issue.** Deliverables 1 and 3 name
   `pq_signing_publickey@<atSign>`; that string appears nowhere in the
   implementation. The issue needs correcting against the code before anyone
   builds on it, and its PR needs a re-review after the pare-back (#2049).

**The general lesson, which is why this is a numbered entry rather than four
comments.** A project's issue and the plan's project entry drift *independently*,
and both drift away from the code. Three of the four above were invisible from
the plan alone, because the plan records what a project set out to do and the
issue records what someone thought it had done. Reading a project's own
deliverable list against the code is a different check from reading the plan,
and it found things the plan's own owed-tables had lost.


### 14.18 The remaining D1 initial-development sequence

Ruled 2026-08-11 by a walk through every open item
([`decisions.md` 93](decisions.md#93-the-d1-remaining-work-sequence-and-the-rollout-axis-becomes-real-2026-08-11)).
This is the **order**, not the inventory — each row points at the entry that
holds the detail — but it is **not** what defines D1's end. **D1 ends when
every acceptance test passes and every rail is green, the posture matrix
included** (gkc, 2026-08-23); this sequence is the work that gets there. ⚠️ This
said D1 "ends at step 34, when the stacked PRs are merged", then briefly that it
ended at the at_auth publish and the rotation arm. Both are superseded.

**Stage 0 — scaffolding.**

| # | Work | Where | State |
|---|------|-------|-------|
| 1 | Drop at_server's `at_commons` override; delete the `at_commons-apsk-1` tag | at_server | **DONE 2026-08-11.** Override gone from both files, `pubspec.lock` resolves hosted 5.14.0, tag deleted local+origin. **[at_server#2744](https://github.com/atsign-foundation/at_server/pull/2744) is MERGED** — corrected 2026-08-13; this row and step 2a both said "open" for a week while `5bc3618a` had become an ancestor of at_server's `origin/trunk`, and the tags `c3.16.0` and `c3.16.1` both contain it. ⚠️ **at_server's 210/210 is still stale** and must be re-earned. `origin/trunk` was `c16f32b0` when this row was written on 2026-08-13 and is `fdb78568` as of 2026-08-14 — re-derive it with `git -C ~/dev/atsign/repos/at_server log --oneline -1 origin/trunk` rather than citing either, since this row records a moving value and nothing here goes red when it moves |
| 2 | Run at_client_sdk's functional pack for the two never-run keyId-shape files | at_client_sdk | **DONE 2026-08-12.** Both pass: `pq_native_onboard_live_test.dart` (UC-A1.1) in the functional pack, and `pq_native_onboard_test.dart` in at_onboarding_cli's pack, both against `at_virtual_env:local`. The run also surfaced the `_apsk` seam break below — 16 of 19 failures, one cause |
| 2a | **The `_apsk` composer moves client-side** — at_server#2744 merged, so the atServer publishes only what a request sends and composes nothing. The client sent nothing, so no `_apsk` existed at approval and every advertised key package was rejected. `EnrollVerbBuilder`/`EnrollParams` gain `apsk` (the array) and `apskLegacy` (the bare RSA string); at_auth composes one or the other at all three submit sites; `parseApskValue` reads the array; the never-published tagged form is deleted | at_client_sdk | **BOTH HALVES DONE.** Client half 2026-08-12, functional pack 127/19 → 143/3. **The atServer half is MERGED too** — corrected 2026-08-13, having been listed as owed after it landed: at_server `6a86fbcc` "feat(at_secondary_server): honour apskLegacy, and bound the whole record" went in via [at_server#2746](https://github.com/atsign-foundation/at_server/pull/2746) (merge `b4ea7cf2`), is an ancestor of `origin/trunk`, and `at_secondary_server` is 3.16.1. ⚠️ **Do not rebuild it.** ✅ **The exercise this row still owed is discharged as of 2026-08-14**, on both arms and against the local image that carries the server code: the **request** arm by rollout-1 enrollments in the matrix, where UC-G1.14 has a released at_client 3.14.0 reader fetch that record and parse it with `RSAPublicKey.fromString` — which succeeds only on the bare form — and the **`enroll:update`** arm by B4's `apsk_server_side_test.dart` row "a healed enrollment advertises its signing key in the bare form", which is the only thing that has ever driven `apskLegacy` on an update — it had been sent solely on the enrolment request. That row is proven discriminating: with the client-side fix reverted it is the only failure of 164 |

**Stage 1 — one envelope shape, one key vocabulary, then the `_apsk` reader
half. Nothing blocks it; start here.** Steps 3–5 are ordered so each shrinks
the next: deleting v1 removes wrapper branches the vocabulary would otherwise
have to carry, and the vocabulary is where `status` is defined before step 5
builds on it.

| # | Work | Detail |
|---|------|--------|
| 3 | **DONE 2026-08-12 — one envelope shape, RFC 7515 general serialization**, `{payload, signatures:[{protected, signature}]}` with `{alg, kid, v}` in each `protected`. Deleted `signedEnvelopeVersion`, `jwsEnvelopeVersion`'s flattened form, `envelopeVersionOf`'s dispatch, the `wrapperFields` ternary in `ApkamSignedAdvertisedKeys.verify`, and `envelopeVersion` as a `PqPosture` axis. Also took `hashingAlgo` off `signEnvelope` — `alg` names the hash, so nothing unsigned selects a routine — and retired UC-C1.3, the rollout's envelope axis, which had nothing left to drive. The `.mjs` adjudicator moved `flattenedVerify` → `generalVerify`; vectors regenerated at `test/vectors/jws_envelope.json`. **Found en route:** `publishPendingLink`'s already-published check compared a top-level `['signature']` the envelope does not have, so `null == null` matched every time and a different link conveyed later was silently never published | [`decisions.md` 95](decisions.md#95-the-envelope-keeps-one-shape-and-a-retained-key-says-so-2026-08-12) ruling 1, **superseding [91](decisions.md#91-signature-agility-the-apkam-auth-key-stops-being-the-enrollments-signing-key-2026-08-11) ruling 12**'s bespoke container |
| 4 | **DONE 2026-08-13 — ruling 2 landed, so all of step 4 is complete and step 6 is unblocked.** Ruling 2 in three commits: `6462ae786` (the advertisement becomes `{v, createdAt, keys:[{use, alg, pub, kid}], suites}` with one `toPayload`/`fromPayload` codec replacing a map literal in `_mint` and a hand parser in `verify` 250 lines apart), `d28ef48a9` (a key that is not its algorithm's length is refused — a kid is the digest of whatever bytes are carried, so it matched a forged key as readily as a real one), `69449603e` (the reader skips entries it has no KEM for and picks the strongest it can use, which has to ship before any writer emits a second key). **Three things the ruling got wrong**, all corrected in `decisions.md` 94: `_apsk` entries never carried `status`; `status` and `KeyEntryStatus` are deferred **entirely to step 5** so no dead field ships (gkc, 2026-08-13); and at_auth cannot reach `PackageKey` because at_client depends on at_auth, so one vocabulary means one **wire spelling** across two Dart types. `createdAt` was added for symmetry with `KeyPackage`; `v` stays 1. Rails: at_client 1188/1188, functional 146/146. One key-entry vocabulary across all three advertising records — `{use, alg, pub, kid, status?}` inside `{v, keys:[…], suites}`. **Landed 2026-08-12:** ruling 3 (one kid function, at_auth's `publicKeyKid`, over the key's raw BYTES — `apskKid` hashed the base64 text and `nskeyKidOf` the material, and every kpid changes value); ruling 4 (`v`, `alg`, `suites` required, both `legacy*Suites` deleted); ruling 5 (one `SecretSharingAlgos.bestSuiteBetween`); **ruling 6** — `pq_envelope.dart`'s `pqSealToBase64`/`pqOpenFromBase64`, both taking `info` and `version` as **required** arguments and constructing neither, so there is nothing inside the shared code for the two substrates to converge onto. at_chops' `pqSeal`/`pqOpen` now require `info` too, which makes a shared binding a **compile error** rather than a convention — it was reachable before, because `info` was optional and `info ?? Uint8List(0)` made omission and empty the same binding. **Found en route:** the pairwise substrate had NO test that could fail on a converged binding — dropping the label from all three pairwise/enrollment call sites left the suite green at 1180/1180 — so the production-fed differential in `pairwise_secret_sharing_test.dart` was built first and proven by that same symmetric mutation, which now turns exactly one test red. **Still owed: ruling 2** — the nskey advertisement gains a `keys` list and adopts the shared spelling | [`decisions.md` 94](decisions.md#94-three-records-advertise-keys-and-only-one-of-them-speaks-the-vocabulary-2026-08-11) — ⚠️ **before step 6**, or that parser becomes the third hand-rolled codec for one shape |
| 5 | **DONE 2026-08-13 — the `retired` key path, in three commits.** `6a5eac838`: `PackageKey` gains `status`, a `KeyEntryStatus` of `active` or `retired`, and `bestKeyFor` on both a key package and an nskey advertisement passes a retired key over, so `kpid` is the *active* enc key's kid. Emitted only when retired — absent already reads as active — and an unrecognised value read as retired. ⚠️ **That last clause held only until 2026-08-22**, when `KeyEntryStatus` became an open String (14.49.1): an unrecognised value is now carried through verbatim and is neither offered for new operations nor trusted to verify old ones. The 2026-08-13 reading was right that it must not be *used*, and wrong that `retired` says so — a retired key still verifies what it signed. `f956b2146`: `PersistedApkamKeys` becomes `{encKeys: [PersistedEncKey]}` and `KeyPackageRegistration` expands, advertises and answers for every held key, with `encKeyFor(kid)` replacing `encSecretKey` and `heldKpids` listing every address. `f6fc3796e`: the sweep, the wake-up subscription and the sync listener cover every held address (`EnvelopeAddressing.regexForAny`/`sweepRegexForAny`), and `_consume` opens with the key the envelope names. **Three things ruling 9 got wrong or omitted**, all recorded in `decisions.md` 95: the sweep filter is a **fifth** consequence and the one that makes the other four reachable; the keyfile already records the status (`CryptographicMaterial.CryptographicMaterialStatus`, `AtKeys.retireKey`, and an `AtKeysAssurance` rule enforcing one active `publicEncapsulation` per enrollment and algorithm), so deriving it from `createdAt` was wrong; and `dead` material is not adopted at all. Rails: at_client 1210/1210, functional 146/146. **Nothing rotates yet** — the writer is step 16. ⚠️ app-facing: `PersistedApkamKeys` is what apps build in `loadApkamKeys`/`saveApkamKeys` | [`decisions.md` 95](decisions.md#95-the-envelope-keeps-one-shape-and-a-retained-key-says-so-2026-08-12) rulings 6–9 — without the plural holding the field is decorative. The **name collision** was settled 2026-08-12 (gkc) and landed as ruled: the per-entry wire value is a Dart `KeyEntryStatus`, and `KeyPackageStatus` — the reader's verdict on a whole package (`present`/`absent`/`rejected`/`unsupported`) — keeps its name. Nothing renamed |
| 6 | **DONE — mostly with step 2a, completed 2026-08-13.** `parseApskValue` reads the array **and** the released bare string, refuses a structured value advertising nothing it understands rather than guessing, and skips entries whose `use` or `alg` it does not know; `apsk_formats_test.dart` covers all of that plus "the array form is unmistakable to a bare-RSA consumer". Finished on 2026-08-13 by giving `ApskSigningKey` a `status` and having `apskSigningKeys` read it — **keeping** a retired entry, because this list is what verifies stored envelopes and a retired key is precisely what signed the older ones. `KeyEntryStatus` moved from at_client to **at_auth** in the same change so all three advertising records name one type, narrowing [94](decisions.md#94-three-records-advertise-keys-and-only-one-of-them-speaks-the-vocabulary-2026-08-11)'s "one vocabulary cannot mean one Dart type" — that was true of a type living in at_client, and at_auth is the lower package. **Found by the re-verify:** `design.md` 9.3's JSON example omitted `kid`, which the reader requires, so the document the design showed is one every reader treats as empty and then refuses; corrected, and pinned. `advertised.first` and the singular `ParsedApsk` are steps 7–9's business, not a gap here | [`design.md` 9.3](../design.md#9-subsystem-g--signature-agility-the-authsigning-key-split) |
| 7 | **DONE 2026-08-13.** `SigningAlgoType.strongestFirst` + `strongestOf` in at_chops — purely additive (two statics on the existing enum; no member added, moved or renamed, so it does not touch the unresolved 3.6.0-versus-major question). Deliberately **not** declaration order: members are declared in the order they were added and reordering them is a wire change, so preference is a second statement. `mldsa65` first, categorically — the only member Shor does not break — then RSA-4096, `ed25519`, `ecc_secp256r1`, RSA-2048 by classical security level. Total on purpose: a partial order leaves the choice undefined for exactly the pair nobody thought about. **The tripwire is completeness, not just the literals**: a new `SigningAlgoType` left out of the order turns `test/signing_strength_test.dart` red, which is what stops it becoming silently unrankable. Wired straight into `parseApskValue`, which took `advertised.first` — the order entries arrive in is the *signer's* choice, so an enrollment advertising ML-DSA-65 beside RSA-2048 was verified against whichever it listed first | [14.17](#1417-signature-agility--complete) |
| 8 | **DONE 2026-08-13.** `requireAlg` is gone rather than rewritten: the algorithm is now *resolved* — from what the envelope's `signatures` and the signer's `_apsk` have in common, taking the strongest by `SigningAlgoType.strongestFirst` — and then its key is fetched, where before one advertised key was taken and the envelope was required to match it. Its refusal survives in a different form: no algorithm in common is refused naming both lists. `ParsedApsk` went plural (`keys`, `keyFor(algo)`; `signingAlgo`/`publicKey` survive as strongest-of getters), and the bare RSA form parses to a one-entry list so both published forms are one shape to the caller. The two JOSE `alg` switches — one on the sign side, one on the verify side — became one `_joseAlgFor`, since two would be two chances to disagree | ⚠️ an inversion, not an addition |
| 9 | **DONE 2026-08-13, with step 8** — the two do not separate: resolving the strongest shared algorithm *is* walking the entries. `verifyEnvelope` selects its entry by algorithm rather than taking `signatures.first`, verifies only that one, and refuses on failure with no fallback. **Found en route and fixed:** `signerEnrollmentId` reads `signatures.first.kid` while the verified entry is now chosen by algorithm, so the two could be different entries — append a signature under a stronger algorithm carrying another kid and a caller acts on a signer whose signature was never checked. `SignedEnvelope.fromJson` now refuses an envelope whose entries name more than one signer, which is a structural claim about this shape rather than a verify-time check. UC-G1.7 is covered for the first time, four rows | [`design.md` 9.4](../design.md#9-subsystem-g--signature-agility-the-authsigning-key-split) |

**A reader understanding no entry refuses outright** — no downgrade, no fallback
to a derivable legacy key ([`decisions.md` 93](decisions.md#93-the-d1-remaining-work-sequence-and-the-rollout-axis-becomes-real-2026-08-11) ruling 2).

**Stage 2 — the unblocker. The writer half cannot start before this.**

| # | Work |
|---|------|
| 10 | **DONE 2026-08-13 — one resolver, not a materialised projection.** `AtKeys.authenticationFor(enrollmentId)` returns the AtChops and the PKAM algorithm, with typed material winning wherever the keyfile holds it for that enrollment and the flat fields answering only where it holds none; `authenticationAlgorithmFor` is the algorithm half, so a caller holding an injected AtChops does not build one `toAtChops` would throw on. `AtAuthImpl.authenticate` and `AtClientImpl._createAtChops` both move onto it. **Ruling 7 as written could not be built** and is amended in place ([`decisions.md` 91.3](decisions.md#913-the-rulings)): filing a projected material makes `toJson` emit `version`/`atsign`/`keys` — the guard is `keys.isEmpty` and both stores stamp `atsign` first — which breaks the byte-identical legacy round-trip [91.4](decisions.md#914-what-is-released-and-therefore-what-must-still-be-read) promises, and on a retrofitted keyfile the one-active-`privateAuthentication`-per-document rule refuses the add outright. Four shipping shapes hold nothing to project from: a pre-typed `.atKeys`, an `rsa2048` first onboard, an OTP enrollment, and an onboard handed its keys by the caller. **Found en route and fixed:** `_createAtChops` picked its keypair off the algorithm `_resolveSigningAlgoFromKeyMaterial` had recorded, and that records nothing when its own read throws — so a transient keyfile failure made a retrofitted client PKAM with the *flat* enrollment's key while its typed material sat in the same file. Its comment claimed it mirrored `AtAuthImpl`; it did not. Rails: at_auth 257/257, at_client 1218/1218 |
| 11 | ✅ **DONE 2026-08-13 — both halves.** ⚠️ This cell was labelled `PARTLY DONE` until 2026-08-18, five days after its own closing clause recorded the second half as done, and 15.2 said so in prose the whole time — a diagnosis is not a correction. **The wiring half.** ⚠️ **The nullability was never the problem, and the blocking claim was measured rather than inherited.** `apkam_signing.dart`'s dartdoc says sourcing from `AtKeys` "cannot land until every client has an `AtKeysIo` — today it is nullable and most apps supply none". Measured over the 22 repos on disk that depend on at_client: **0 of 22** supply one to a client and **0 of 22** use `fromAuthSession`, so the claim is TRUE — but the dominant cause is one SDK line, not app behaviour. `AtOnboardingServiceImpl.authenticate()` built a `FileAtKeysIo` for `AtAuth` and then created the client without it, so every `at_cli_commons` consumer (at_talk, sshnoports, noports-tools, at_demos, ogentic) inherited a source-less client. **Fixed:** `_initAtClient` takes the source and threads it to `setCurrentAtSign`. The injected AtChops still authenticates — this only gives the client the source for what AtChops cannot answer. ⚠️ **Deliberately NOT done: an `atKeysIo ??=` default on at_client_flutter's `AuthService.authenticate()`.** `AtAuthRequest`'s constructor already refuses a request with neither `atKeysIo` nor `atAuthKeys`, so the default could only ever fire when the caller supplied `atAuthKeys` — an app that loaded its own key material — and pointing it at a keychain that may hold another atSign's keys, or none, is a guess. The asymmetry with `onboard()`'s `??=` is correct: onboarding mints keys and needs somewhere to write them. ⚠️ **The null case is a tested, deliberate property**, not an oversight — `no_atkeysio_inertness_test.dart` pins that a source-less client performs zero PQ writes at startup, which is what protects the long-lived cicd atServers, and the e2e pack builds its clients through `setCurrentAtSign` directly so this change does not reach them. ✅ **DONE 2026-08-13, with step 12:** the signing half — `signingKeys` sources from `AtKeys` rather than reading the APKAM auth keypair out of `atChops`. Built once, as step 12's per-algorithm accessor |
| 12 | ✅ **DONE 2026-08-13.** `AtKeys.signingKeysFor(enrollmentId)` (at_auth) returns every active signing keypair the enrollment holds, one per algorithm, strongest first; `ApkamSigning.signingKeys` (at_client) is a `Future<List<ApkamSigningKeys>>` reading it through `AtClient.atKeysIo`. `ApkamSigningKeys` now carries its `algorithm` and `signEnvelope` takes it from there rather than a separate `signingAlgo` argument — a key and an algorithm arriving separately can disagree, and the resulting signature verifies against nothing. ⚠️ **Selection is by the keyId shape `sign:<enrollmentId>:<algo>:<n>`, NOT by the `privateSigning` role**: `PqSigningRoot` files the atSign-wide signing root under that same role with no enrollment id, so a role filter hands an enrollment a key that was never its own — the same defect shape as 14.19 item 6. Proven by mutation: selecting on the role turns two tests red. **The empty case answers with the APKAM authentication keypair**, which is what ruling 10 keeps in the `_apsk` array permanently, so the accessor is live from this commit rather than waiting on a writer, and `now`-posture envelopes stay byte-identical (the stored JWS vector re-signs to the same bytes). That also covers the source-less client, which is a deliberate tested property. Read per call, not cached: a cached copy goes stale the moment a rotation retires what it held. **The minting/filing half is NOT here** — `fileSigningMaterial` still has no production writer, and which algorithms to mint is the in-use set's decision, so it stays step 18. Rails: at_client **1228/1228** (2 skipped), at_auth **266/266** |

**Stage 3 — the `_apsk` writer half (rollout 2).**

| # | Work |
|---|------|
| 13 | ✅ **DONE 2026-08-13.** `apskAdvertisement` composes from a **list** of keys rather than one `(apkamPublicKey, signingAlgo)` pair, so a second algorithm's key can be advertised beside the first; `ApskSigningKey.forPublicKey` builds an entry and derives its `kid`, which is never a caller's to supply. `status` is emitted **only when retired**, so an advertisement that has never rotated is byte-identical to what the single-key composer wrote. The enrollment-request site still sends one key — at request time the enrollment holds nothing but its freshly minted APKAM keypair, and a second arrives by `enroll:update` (step 16) once step 18 mints one. **`publishPublicSigningKey`'s fate, settled:** it stays the only writer for an `_apsk` no `enroll:request` can carry (a client with no enrollment publishes under `primary`, which has no enrollment record). It now publishes `publicSigningKeyValue` — the **bare** key when the client holds exactly one `rsa2048` key, the array otherwise — which is the same rule `_apskFor` uses for `apsk`-versus-`apskLegacy`; the two must agree because they describe one record. It also **republishes on a change**, closing [decisions.md 91.1](decisions.md#911-what-is-wrong-today) cost 2: it used to read the record, log "have already published" and return, so a rotated key never reached the atServer and every envelope signed with the new one was verified against the old. Proven by mutation: restoring the absent-only condition turns exactly the republish test red. Rails: at_client **1234/1234** (2 skipped), at_auth **269/269** |
| 14 | *(done in step 2a)* `EnrollParams.apsk`/`apskLegacy` are populated at all three submit sites. ⚠️ **This read "Only the atServer half of `apskLegacy` remains" until the 2026-08-14 wrap-up, and that half had merged two days earlier** — at_server `6a86fbcc`, an ancestor of `origin/trunk`, re-verified with `git -C ~/dev/atsign/repos/at_server branch -r --contains 6a86fbcc`. Step 2a was corrected on 2026-08-13 and this row was not, which is how a reader working top-down would have rebuilt merged work |
| 15 | ✅ **DONE 2026-08-13.** `signEnvelope` takes a **list** of keys and emits one signature entry per key, in the order given — which is what the RFC 7515 general serialization the envelope already used is for. `wrapAndSign` passes every key `signingKeys` returns rather than its strongest: the **verifier** chooses, taking the strongest algorithm the envelope and the published `_apsk` share, so signing only under this build's strongest would be unverifiable to any peer that has not implemented it — an envelope carrying both is readable by the upgraded peer and the un-upgraded one, which is the rollout problem in one sentence. The payload is encoded **once** and every entry signs its own protected header joined to that same text, so the entries are alternatives rather than a chain. `SignedEnvelope.fromJson` already refused an empty signatures array and a multi-**signer** document, so the writer builds through it and inherits both refusals. ⚠️ **UC-G1.7's two-signature fixture was hand-assembled** from two single-signature envelopes, so that whole group was a test of the fixture and would have passed against a writer that could not emit two signatures at all; it now drives the real writer. Proven by mutation: signing with `[keys.first]` turns the multi-signature test red. Nothing files per-algorithm signing material yet, so every envelope still carries exactly one signature today, and the stored JWS vector re-signs byte-identically. Rails: at_client **1237/1237** (2 skipped), at_auth **269/269** |
| 16 | ✅ **DONE 2026-08-13, in five commits `e04040ac1`…`d467ed3b5`** — two code, three docs (this row said "in two commits", written before the doc sweep and the wrap-up corrections landed). `AtEnrollment.update` takes an `EnrollmentUpdateRequest` and an `EnrollmentUpdater` sends it, beside `EnrollmentApprover` and deliberately not on it: the approver's verbs need a connection holding `__manage` and act on somebody else's enrollment, while this one needs no privilege and can only act on the enrollment the connection *is* — the atServer refuses an owner connection here rather than waving it through. The request refuses at construction to be built naming nothing to change, with a public key and no private half, with a key and no algorithm or an algorithm and no key, with both `_apsk` shapes, or with an advertisement of no keys. **Found en route: the wire vocabulary was one field short, so this row's "only the caller is owed" was wrong.** `EnrollParams.apkamPublicKeySignature` existed with its own round-trip test, but `EnrollVerbBuilder.buildCommand` never copied it into the params it builds — and a `toJson`/`fromJson` round trip is equally true of a field nothing can send, so the test could not see it. **Two rulings this took:** `signingAlgo` is **always** sent, so the effective algorithm the atServer interpolates is the one signed here and the literal `"null"` can never come from this emitter (pinned regardless — a second implementation has to know the server accepts it); and the public API takes two key-material **strings**, not an `AtPkamKeyPair`, because at_chops deprecates that type and a new signature carrying it hands every caller a deprecation. `ecc_secp256r1` is refused rather than signed: at_chops' pkam-mode signer selects an RSA implementation for everything that is not `mldsa65`, so an ECC key would be signed as though it were RSA — and an ECC APKAM key lives in a secure element whose private half is not a string anyone can pass. **Proven by two mutations**, against tests that re-run the atServer's own `ApkamSignatureVerifier` branches rather than asserting through the signer: signing everything as `rsa2048` turns exactly the mldsa65 arm red (that arm is the only one that can see an algorithm mix-up), and dropping the algorithm from the signable turns all three signature tests red (both arms verify real bytes). ⚠️ **Nothing persists a rotated keypair** — [14.19 item 11](#1419-small-items-raised-2026-08-12-and-not-yet-acted-on). Rails: at_commons **517/517**, at_auth **288/288**, at_client **1237/1237** (2 skipped), at_onboarding_cli **39/39**. **THE PoP CONTRACT, read from at_server `6a86fbcc` `enroll_verb_handler.dart` `_verifyApkamPublicKeyPossession` and `apkam_signature_verifier.dart` — do not re-derive it:** signable is `utf8.encode('<enrollmentId>|<apkamPublicKey>|<signingAlgo>')`, signature travels **base64**, signed by the **NEW** private key. Three things a guess gets wrong: (a) `signingAlgo` is the **effective** one, `request.signingAlgo ?? record.signingAlgo`, string-interpolated — so a null becomes the literal `"null"` in the signed bytes, and a client that omits it must know the record's current value; (b) **mldsa65 signs the message DIRECTLY with no hash** (`MlDsa65PureDartAlgo.verifyBytes`), while rsa2048/ecc go through `AtChopsImpl.verify` with `HashingAlgoType.sha256` — a client that hashes for both fails only on the PQ path; (c) `AtSigningMode.pkam`, never `data`, which signs with the *encryption* keypair. The server also refuses `signingAlgo` without `apkamPublicKey`, and `enroll:update` is **self-only** and **approved-only**. ⚠️ **Adding a member to `AtEnrollment` touched 7 `Mock implements` in three packages** (at_auth 2, at_client 4, at_onboarding_cli 1), plus `AtEnrollmentImpl`, which is the **production** class and got a real implementation rather than a stub — not an eighth mock, as an earlier draft of this row said. All three suites re-run; the mocks are safe because no production path calls the new member, and they would have broken at RUNTIME, not analyze |
| 17 | ✅ **DONE 2026-08-13.** `AtClientPreference.dataSigningKeyAlgorithms` — a `Set<SigningAlgoType>`, final at construction and stored unmodifiable, defaulted from a new fifth `PqPosture` axis and overridable per preference. **The four things ruling 16 left open were ruled by gkc and are recorded in [`decisions.md` 91.3](decisions.md#913-the-rulings) ruling 16 with their reasoning:** defaults `{}` in 3.x and `{mldsa65}` in 4.0; a `Set`; final at construction; and an algorithm this build cannot sign an envelope under is refused at construction with an `ArgumentError` rather than skipped. ⚠️ **The doc sweep this owed was bigger than the row** — three documents enumerated the posture's axes and all three still listed the **signed-envelope version**, deleted at step 3: [`decisions.md` 56.4](decisions.md#564-from-the-pq-projects-view-40-is-final-3x-with-different-flag-defaults)'s table, its capstone entry [`decisions.md` 70](decisions.md#70-workstream-a-capstone-pqposture-the-five-flags-as-one-value-2026-08-10), and `roadmap.md`'s axis list. The count stayed five across the swap, which is precisely how a stale enumeration survives review. Acceptance gained UC-C1.7 and UC-C1.6's "UC-C1.1–C1.5 prove the arms" was corrected — C1.3 is withdrawn. `design.md` 9.6's strength order still showed the three-member ruling rather than the five-member total order step 7 shipped. **Nothing reads the set yet — step 18 is its only consumer**, so this commit is a preference and its refusal, not a behaviour change. **Proven by four mutations**: each posture default flipped reddens its literal pin, disabling the signable check reddens the refusal test, and returning the caller's own set rather than an unmodifiable copy reddens the containment test. ⚠️ **The 1240/1240 in this commit's message was measured before the doc edits and does not hold for the commit as landed** — adding UC-C1.7 to `acceptance.md` without a scenario in `test/acceptance/` turns `catalogue_test.dart` red, which is that guard doing its job. Fixed in step 18's first commit, which adds the scenario and the README row count. Rails for 17+18a together: at_client **1245/1245** (2 skipped), acceptance **57** (2 skipped) |
| 18 | **PART 1 DONE 2026-08-13 — the reader and the advertisement; the minter is part 2.** Splitting it was forced by a defect the minter would have shipped: `ParsedApsk.keyFor` took **one key per algorithm** (`where(alg).firstOrNull`) and `verifyEnvelope` checked that one, so ruling 10's retained authentication key works only where its algorithm differs from the minted key's. A post-quantum-native enrollment's auth key is ML-DSA and so is what it mints, which puts two `mldsa65` entries in `_apsk`, and every envelope signed before the split stops verifying — the ordinary 4.0 case. `keysFor(algo)` is now plural and the verifier tries each, refusing only when none verifies; ruling 10 is amended in place with why. **The reader ships before the writer**, which is also why this is two commits rather than one. Also here: `apskEntries`/`apskValueOf` (`apsk_composition.dart`) are the one composition of the `_apsk` record for both its publishers, and they append the authentication key as `retired` once the enrollment holds signing keys — deduped, because one key described as both current and withdrawn is a document a verifier has nothing to choose on. An enrollment holding no signing material advertises exactly what it did before. ⚠️ **The retention half was reversed 2026-08-14 by row B2** under [`decisions.md` 98](decisions.md#98-rollout-1-moves-the-authentication-key-not-the-signing-key-2026-08-14) ruling 2: the auth key is advertised only while it *is* the signer and is never retained, and what `apskEntries` carries beside the active signers is the enrollment's **retired signing keys**. The dedup survives, between an active signer and a retired entry naming the same public half. **Proven by mutation**: restoring the single-key selection reddens the retained-key test. Rails: at_client **1245/1245** (2 skipped), acceptance **57** (2 skipped). ~~**Part 2 owes** the minter itself: mint at start, publish, then file.~~ ✅ **PART 2 DONE 2026-08-13** (`90730a130`, "an enrollment mints its own signing keys, advertising before filing"), and this sentence stayed here reading as owed until 2026-08-18. `SigningKeyMinting` (`signing/signing_key_minting.dart`) mints one keypair per algorithm the in-use set names and the enrollment lacks, retires every held one the set no longer names, and is wired as step 3 of `PqClientBootstrap` (`pq_client_bootstrap.dart:203`); `test/signing_key_minting_test.dart` covers it and `tests/at_functional_test/test/apsk_server_side_test.dart:215` drives it live. The order it owed is the order it shipped in. ⚠️ **That order matters** — filing first makes the client sign with a key its advertisement does not name, and every envelope written in that window is permanently unverifiable, while an advertised key that was never filed costs a verifier nothing and disappears at the next publish. The nskey path's rule is the opposite (`NskeyPrivateFiling.store` files before publishing) because an unopenable *encapsulation* key loses data; the asymmetry is real and worth stating where both are read |
| 18b | ✅ **DONE 2026-08-13.** `SigningKeyMinting` (at_client) mints a keypair for every algorithm the in-use set names and the enrollment does not hold, advertises it, and **then** files it through `WrittenAtKeysIo.update` — the store's atomic verb, because a client's start files conveyed key material through the same keyfile and a hand-rolled read → mutate → write would drop whichever addition flushed first. Wired as the **ninth** `PqClientBootstrap` step, `mintInUseSigningKeys`, gated by `PqStartupGates` and placed **before every step that signs** (seeding, both link publications and the sweep all emit signed envelopes), so a key minted on a start is advertised before anything signs with it. Which writer depends on whether there is an enrollment record: `enroll:update` where there is one — the atServer is the only writer of an enrollment's `_apsk` — and a direct publish under `primary` where there is not. Inert with an empty in-use set (the 3.x default) and inert for a client with no key source, which is the tested no-`AtKeysIo` property. `RsaKeyPair.generate()` rather than `AtChopsUtil.generateAtPkamKeyPair()`, which returns a type at_chops deprecates. **Proven by three mutations**: swapping to file-then-publish reddens the ordering test, dropping the retained authentication key reddens the advertisement tests, and minting an already-held algorithm reddens both idempotence tests. ⚠️ **The second of those mutations no longer discriminates** — row B2 removed the retention it was probing. Its replacement is B2's own pair: gutting the withdrawn-signing-key selector (`retiredSigningKeysFor` on the day, `withdrawnSigningKeysFor` since 2026-08-22) reddens the two retained-signing-key tests, and removing the dedup reddens the third. Rails: at_client **1257/1257** (2 skipped), acceptance **57** (2 skipped) |
| — | *(the original row, kept for its spec pointers)* Mint-on-demand when the in-use set names an algorithm the enrollment lacks. **Spec: ruling 16** (mint locally at start, file it, publish it — a *signing* keypair may, because unlike the auth key it needs no server approval) and **[`decisions.md` 91.3](decisions.md#913-the-rulings) ruling 9** (the array is append-mostly: an algorithm leaving the set stops signing, but its key and its published entry are **retained**, because they are what verify the envelopes it already signed). This is the step that gives `signingKeysFor` something to read — `fileSigningMaterial` has no production writer until it lands |
| 19 | ✅ **DONE 2026-08-13.** The axis is **`SigningRollout`** — `now` / `rollout1` / `rollout2` — on `PqPosture.signingRollout`, overridable per `AtClientPreference`, with the in-use signing set **derived** from it rather than stored beside it. **The step opened with a finding that nearly closed it:** the three rollout-2 writer behaviours are inseparable *by construction*, not by three flags agreeing — only minting is a decision, while the array form (`apskValueOf` emits the bare string only for a single active `rsa2048` entry) and the multi-signature envelope (`wrapAndSign` signs with every key the keyfile holds) are consequences of the enrollment holding a second key. Folding the axis away like step 23 was put to gkc and **declined**: the axis earns its place by naming the position, and steps 20–22's driver needs those names. So it names a position and supplies one default, and cannot contradict the behaviour — two stored fields would be two controls over one thing. `rollout1` writes exactly what `now` writes (the reader half needs no gate) and carries the *fleet's* position instead; it is reachable only through the preference, since there are two postures and no general constructor, and an unreachable value would be a rollout position nothing could ever be in. **Proven by three mutations**: giving `rollout1` a non-empty set, ignoring an explicit stage, and letting the stage beat an explicit set each redden their own arm. Rails: at_client **1261/1261** (2 skipped), functional **146/146** at `88ab87b4e` |

⚠️ **The rollout stages were REDEFINED 2026-08-14, and the at-rest keyfile
shape with them. NONE of it is built.** Read
[`decisions.md` 98](decisions.md#98-rollout-1-moves-the-authentication-key-not-the-signing-key-2026-08-14)
and [99](decisions.md#99-the-keyfile-groups-by-enrollment-and-the-atsigns-own-keys-move-out-2026-08-14)
for what and why, and **[14.20](#1420-building-rulings-98-and-99--the-sequence)
for the order to build them in** — several of those orderings are the difference
between a working rollout and a broken fleet. Read all three before acting on
any row below that names a stage. Rollout 1 now moves the
**authentication** key to ML-DSA-65 and mints a fresh **RSA-2048 signing key**
to advertise in its place: only the atServer verifies the auth key, while every
peer verifies the signing key, so the forgeable-later credential can move first
while the verification surface stays classical. Consequences that touch rows
already marked done:

- ✅ **DONE 2026-08-14 (row B1).** `SigningRollout`'s in-use sets became `{}` /
  `{rsa2048}` / `{mldsa65}`, and it gained
  `defaultRetrofitAuthenticationAlgo`; `retrofitSigningAlgo` is renamed
  `retrofitAuthenticationAlgo` and is now a derived getter (step 17/19's
  landed work, extended).
- `_apskFor` must advertise the **signing** key, not `apkamPublicKey`, and the
  retrofit must mint that key **before** submitting — otherwise a rollout-1
  enrollment publishes an ML-DSA array at creation and breaks every deployed
  reader (step 2a/13's composer, changed).
- `apskEntries` stops appending the authentication key unconditionally;
  [`decisions.md` 91.3](decisions.md#913-the-rulings) ruling 10 is superseded
  and ruling 9 preserved (step 18a's composer, changed).
- **Rollout 1 needs no APKAM rotation**, so it depends on neither step 20's
  rotation arm nor the at_auth release — it is buildable today.

**Stage 4 — the programme pair. This is the validation gate before any PR is carved.**

| # | Work |
|---|------|
| 20 | **MOSTLY DONE 2026-08-14 — the pair runs; the rotation arm is not built.** `tests/pq_matrix/` holds `scenario/`, `current/` and `published/`, three standalone packages. What is built and driven: the stage parameterisation, a real notification, multiple puts and gets with each put read back at the write. **Still owed: enrollment followed by an `enroll:update` APKAM rotation mid-run.** ⚠️ **Its blocker is now an at_auth RELEASE, not a ruling** — [14.19 item 11](#1419-small-items-raised-2026-08-12-and-not-yet-acted-on) was ruled two-phase on 2026-08-14 and its reader half has landed, so what remains is: publish at_auth carrying the tolerant reader, then add the staged status value, then build the arm. It also needs a dedicated CRAM atSign, since the matrix's demo atSigns hold no enrollment. Do not re-open the persist-before-versus-after question |
| 21 | ✅ **DONE 2026-08-14.** `tests/at_functional_test/test/pq_rollout_matrix_test.dart` runs all sixteen cells, sender and receiver as separate **processes** — they are separate builds, and no one process can hold two versions of at_client. The receiver is spawned first and the sender waits on its `READY` line, because notification streams are broadcast and do not replay. Every cell passes; the failing cells the row used to describe were measured out of existence (see the warning below). **Proven by mutation**: a sender writing `putCount - 1` records reddens the cell, and the error names the missing record, so the receiver genuinely reads from the atServer rather than passing on an empty comparison |
| 22 | ⚠️ **DONE 2026-08-14, then SUPERSEDED the same day.** The row it proves was rewritten by [`decisions.md` 98](decisions.md#98-rollout-1-moves-the-authentication-key-not-the-signing-key-2026-08-14) ruling 12: rollout 1 publishes a *different key* from `now`, so byte-identity is false by design and the test as landed asserts something that will stop being true the moment the stages are rebuilt. Its replacement asserts the **form** instead, measured by the published arm — a released at_client 3.14.0 reader fetching a rollout-1 sender's `_apsk` and base64-decoding it as an RSA key. **The positive control is the part to keep**: whatever the row asserts, a rollout-2 cell must differ, or it passes for a harness where no stage does anything. *What landed, for the record:* UC-G1.14 runs its own now/now and rollout1/rollout1 cells rather than reading what the matrix loop left behind — a test that depends on another test having run first passes on declaration order, which is not a property of the code. It asserts the published `_apsk` byte-identical and the sender's keyfile byte-identical across the two stages. **It carries its own positive control**, and that is the part worth keeping: a third cell at rollout2 must *differ* on both counts. Without it the row passes just as well for a harness where no stage does anything — which is exactly how a rollout-2 arm attached with no key source reads. Measured: `now` and `rollout1` leave the keyfile at its 5605-byte baseline, `rollout2` leaves 14016 |

Scope of the pair, ruled: the signed-envelope exchange; a real notification and
data path; **multiple puts and gets**; and enrollment followed by an
`enroll:update` APKAM rotation mid-run. The **published** arm runs the last
released at_client and is what makes "`now` is faithful to legacy" a
measurement rather than a claim — see [`acceptance.md` 16.1](../acceptance.md#161-the-harness).

**Where it lives, ruled 2026-08-14** ([`decisions.md` 96](decisions.md#96-the-programme-pair-gets-a-home-outside-the-workspace-2026-08-14)):
`tests/pq_matrix/` holding `scenario/`, `current/` and `published/` as three
**standalone** packages — none listed in the root `workspace:`, because
`packages/at_client` is a workspace member and a member cannot depend on the
hosted 3.14.0. `published/` pins `at_client: 3.14.0` exactly with its lockfile
committed; `scenario/` holds the exchange once and each arm supplies only its
own preference construction, so a published-versus-`now` divergence is
attributable to at_client rather than to two hand-written programs. The driver
is a test file in `tests/at_functional_test`, so `runLocal.sh` stays the entry
point.

⚠️ **The matrix is a data-path matrix, and the two failing cells are gone.**
Measured 2026-08-14: at_client 3.14.0 and this tree cannot exchange an envelope
in **either** direction under **any** stage — this tree → 3.14.0 is a
`_TypeError` null cast, 3.14.0 → this tree refuses with "an envelope must carry
its payload as a string". Step 3 deleted the envelope as a posture axis, so no
stage emits the released shape. gkc ruled the break accepted rather than fixed,
on reachability: the released reader is same-atSign only, hangs off an
`@experimental` entry point nothing in 3.14.0 constructs, and that entry point's
dartdoc opens "not yet suitable for production secrets". Both errors are pinned
as raw literals. The rollout-2 cells previously shown as failing with
`IllegalStateException` were wrong on both the cells and the error —
[`acceptance.md` 16.5](../acceptance.md#165-the-rollout-matrix) records what it
used to say, and [`decisions.md` 95](decisions.md#95-the-envelope-keeps-one-shape-and-a-retained-key-says-so-2026-08-12)
rulings 2 and 3 are amended in place.

**Stage 5 — the rest of D1. All in scope; none deferred.**

| # | Work | Entry |
|---|------|-------|
| 23 | *(folded away)* passive-by-default **is** the axis's `now` position | [14.13](#1413-a-passive-by-default-flag-surveyed-not-built) |
| 24 | A client with no enrollment id is treated as fully privileged | [14.14](#1414-a-client-with-no-enrollment-id-is-treated-as-fully-privileged) |
| 25 | A `mintLegacyMaterial:false` atSign cannot write a public record | [14.12](#1412-a-mintlegacymaterialfalse-atsign-cannot-write-a-public-record) |
| 26 | *(closed)* revocation visibility — an `EnrollmentManager` cache race, fixed in at_server `16dd457f`. ⚠️ This cell said "a proven test-instrument failure" until 2026-08-15; that was the 2026-08-11 ruling the root-cause overturned | [14.9](#149-a-revoked-enrollment-can-still-authenticate-briefly) |
| 27 | ✅ **DONE 2026-08-15** — domain separation on the signed envelope, per-use `typ` plus a root-link prefix ([`decisions.md` 103](decisions.md#103-an-envelope-says-what-it-is-for-and-a-verifier-says-what-it-wants-2026-08-15)) | [14.8](#148-domain-separation-on-the-signed-envelope) |
| 28 | NoPorts' own copy of the envelope shape | [14.7](#147-noports-carries-its-own-copy-of-the-envelope-shape) |
| 29 | **Three** audit residuals — perf ceiling on a real low-end device, SS-4 interrupted-mint resume, IS-1 record-name drift. ⚠️ This read **four**, including UC-A3.4's live self-direction, until 2026-08-18 — 14.16's own body has marked that ✅ DONE since 2026-08-17 | [14.16](#1416-four-residuals-the-issue-tree-audit-surfaced-2026-08-09) |
| 30 | `deprecated_member_use` findings across the workspace — *2026-08-13 snapshot: 340 at_client, 183 at_onboarding_cli, 110 at_auth, 28 at_lookup. Re-measured 2026-08-23: **396 / 205 / 153 / 0**, five buckets, only bucket B is D1 work* | [14.11](#1411-deprecated_member_use-findings-across-the-workspace) |
| 31 | Pre-PR rails checklist | [14.15](#1415-pre-pr-rails-checklist) |

Also in D1, runnable in parallel: **S-3**'s completion, **B-3** ([#2128](https://github.com/atsign-foundation/at_client_sdk/issues/2128),
open), **KF-1** ([#2129](https://github.com/atsign-foundation/at_client_sdk/issues/2129),
open), and **IS-1**. ~~merging at_lookup 3.6.1 (#2127)~~ — dropped 2026-08-13:
that PR merged 2026-08-08 and 3.6.1 is on pub.dev, so it had been listed as
parallel work for five days after it was finished. Issue states verified with
`gh` on 2026-08-13; re-derive rather than trusting this line.

**Stage 6 — the carve-up, which is where D1 initial development ends.**

| # | Work |
|---|------|
| 32 | Carve the spike into stacked PRs |
| 33 | Merge them to trunk. **The spike branch itself never merges** |
| 34 | ← D1 initial development complete here |

Then, as the release programme rather than development: publish at_chops 3.6.0
→ at_commons **5.16.0** → at_auth **4.0.0-rc1** → at_client's GA minor, and finally
**R-2**, the 4.0.0 posture flip. (⚠️ this said at_commons **5.15.0** until
2026-08-13, a version already on pub.dev; the in-tree in-progress heading is
5.16.0. Check pub.dev against every touched pubspec before acting on this
ladder — a same-value version bump merges silently.)

### 14.19 Small items, raised 2026-08-12 and not yet acted on

⛔ **TRIAGED 2026-08-23 by gkc. The headline count overstates the work, which
is why it keeps being re-argued.** Of the 15 items the counter now reports as
open: **three are not work at all** — 20, 21 and 26, each of which says so in
its own text ("deliberately left", "accepted … recorded so it is not
rediscovered", "that is deliberate") — and **two belong elsewhere**: 14 is not
PQ (16 `atProtocol` spellings outside this doc set) and 35 lands in
`atGettingStarted`. That leaves **six genuinely open**: 2, 4, 10, 28, 29 and 34.
⚠️ This read "**seven genuinely open**: 2, 4, 10, 28, 29, 34 and **36**".

✅ **Item 36 — the only D1 GATE among them — is CLOSED 2026-08-24**, and this
paragraph read "⛔ **Item 36 is a D1 GATE**; the other six are not." Its three
clauses are live-proven in
`tests/at_functional_test/test/key_package_amendment_live_test.dart`. D1 still
ends when the acceptance set is complete, implemented and verified; what item
36 named — the one known case of the catalogue asserting clauses no live row
proves — is discharged, and the ledger's clause level now computes any
successor rather than leaving it to a reader. Items 8, 23
and 30 were settled the same day and carry their rulings in place.

Each is real, verified at the time of writing, and too small to be a step of
its own. None blocks anything.

1. ~~**`packages/at_client/lib/src/exception/at_client_exception.dart` is
   dead.**~~ **DELETED 2026-08-17.** Re-verified before deleting rather than
   trusting the 2026-08-12 grep: zero importers of that path anywhere in the
   workspace, absent from the barrel, and both classes `@Deprecated` since the
   types moved to at_commons. The directory went with it — it held nothing
   else. Not a public-API change: it was reachable only by a deep
   `package:at_client/src/…` import.
2. **`at_commons`' `KeyUtil` (`lib/src/keystore/at_key_util.dart`) has zero
   callers** anywhere in the workspace — but unlike the above it IS published
   public API, so removing it is a deprecate-then-delete, not an edit.
3. ~~**`enrollment_service_test.dart:206` asserts
   `(metadata!['keyPackage'] as Map)['signature'] == 'sig'`** against an opaque
   stub.~~ **FIXED 2026-08-17.** The stub no longer mimics an envelope at all —
   it is `{"opaqueToTheClient":true}`, which is what the client actually treats
   the metadata as. ⚠️ **Three stubs carried the shape, not the one this row
   named**: the same `{"payload":…,"signature":…}` sat in two neighbouring
   tests, so fixing only line 206 would have left the misleading documentation
   two lines away. The assertion now says in a comment why the stub is shaped
   the way it is.
4. **Every kpid changed value** at
   [`8d44a9222`](#1418-the-remaining-d1-initial-development-sequence) (step 4,
   ruling 3 — the kid preimage became the key's raw bytes). Licensed by ruling
   94.4 and the `@experimental` marker, and nothing published reads a kpid. The
   operational consequence: **a long-lived local virtualenv holding enrollments
   minted before that commit derives different kpids than it did**, so recycle
   it before trusting their key packages. A fresh `runLocal.sh` run is
   unaffected — it recycles the container anyway.
6. ~~**`_keyPackageHalves` can adopt a co-tenant's key package.**~~ **FIXED
   2026-08-13** by routing through `keyPackageMaterial`, exactly as the entry
   below proposed. **A second defect came with it, unrecorded until now:** an
   nskey private is filed under the same `privateDecapsulation` part type but
   arrives *alone*, so the hand-rolled selection could adopt one as this
   enrollment's recipient identity — `keyPackageMaterials`' requirement that
   both halves share a keyId is what excludes it, and its own dartdoc had
   named that hazard all along. ⚠️ **The test fixture was standing in for a
   shape production never produces**: `withKeyPackage()` filed only the private
   half, while `enrollmentKeyPackageBuilder` (`enrollment_key_package.dart:101-110`)
   files both. Reverting the fix turns both new rows red. Original finding:
   `enrollment_symmetric_key.dart`'s `_keyPackageHalves` selects the private
   half with `firstOrNull` over an unsorted list, scoping by neither enrollment
   id nor recency — where `keyPackageMaterials` does both, deliberately, and
   documents why. On a **retrofitted** keyfile, which carries the legacy
   enrollment's package alongside the new one, it can pick the wrong principal's
   key and then poll for envelopes at an address nobody is writing to until it
   times out, failing the enrollment. Real, unfixed, and pre-existing: it is
   about *scoping*, not about the plural holding
   [14.18](#1418-the-remaining-d1-initial-development-sequence) step 5 landed,
   which is why that step deliberately left this site singular
   ([`decisions.md` 68.5](decisions.md#685-the-receiver-becomes-multi-kpid)).
   The fix is to route it through `keyPackageMaterials`, which already answers
   this question correctly, rather than to add a second selection rule.

5. ~~**One bad peer aborts a whole secret broadcast.**~~ **FIXED 2026-08-13.**
   ⚠️ **The blast radius was two methods, not one:**
   `pushSecretToNamespaceMembers` has the identical unguarded loop and was
   fixed with it. `shareAllSecretsWith` was deliberately left alone — it loops
   *secrets* for one recipient, so a throw there means that recipient is
   unreachable rather than the broadcast dying early. **Left unruled:**
   `shareAllSecretsWithEnrollment` loops one enrollment's several packages and
   aborts on the first failure; that is the same shape for addresses rather
   than principals, and wants a decision rather than a copied guard.
   ⚠️ **The reachable case is not the one the entry below names.**
   `sendEnvelope` throws twice: once when the peer advertises no key with a
   supported *algorithm*, and once when there is no mutually supported
   *suite*. The loop's own `to.kpid != null` guard already filtered the first
   — that is what the existing "no mutually-supported key is skipped" group
   covers — so only the second could ever abort a broadcast, and a peer
   reaching it has a perfectly good kpid. Both new rows go red when the guards
   rethrow. Original finding:
   `PairwiseSecretSharing.requestSecretsFromNamespace` awaits `sendEnvelope`
   per member with no guard, so `sendEnvelope`'s own documented `StateError`
   (one member advertising no mutually supported construction) stops the loop
   and every remaining member is never asked. That undercuts the N-holders
   design `requestAnswerJitter` exists to manage. Real, unfixed, and
   deliberately not folded into the ruling-6 commits because it has nothing to
   do with domain separation — it wants its own subject line and its own test.

7. ~~**An APKAM filed under an algorithm this build does not recognise falls
   back to the flat fields.**~~ **FIXED 2026-08-13.** `authenticationFor` now
   refuses with an `AtKeyNotFoundException` naming the algorithm, and
   "this enrollment has no typed material" stays a separate answer that still
   reaches the flat fields. Original finding: `signingAlgorithmForEnrollment` matches the
   material's `algorithm` against `SigningAlgoType.values` and returns
   null for anything else, and `authenticationFor` reads null as "no typed
   material for this enrollment" — so a keyfile written by a newer client
   authenticates from the flat fields instead, which on a retrofitted file are
   a *different* enrollment's credentials. The two cases are not the same
   question: "this enrollment has no typed material" and "it has some I cannot
   sign with" want different answers, and only the first should reach the flat
   fields. Not reachable today — `CryptographicMaterialAlgorithm`'s signing tokens and
   `SigningAlgoType`'s names agree exactly — so this is a forward-compatibility
   hole rather than a live defect. [14.18](#1418-the-remaining-d1-initial-development-sequence)
   step 10 is what makes it a one-line fix: the decision now lives in one
   place.
8. **Typed key material is not self-encrypted at rest; the flat fields are.**
   `file_io.dart`'s `_selfEncryptedLegacyFields` names exactly four keys —
   `aesPkamPublicKey`, `aesPkamPrivateKey`, `aesEncryptPublicKey`,
   `aesEncryptPrivateKey` — and nothing else in `packages/at_auth/lib/src/keys/`
   encrypts anything. So a PQ-native keyfile's ML-DSA APKAM **private** key is
   written in the clear, while the RSA private key of a legacy keyfile beside
   it is not, and the only thing covering the typed section is the optional
   passphrase envelope. Worth a ruling rather than a patch: extending the
   self-encryption to the typed section changes the at-rest format, and the
   passphrase envelope may be the answer instead.

   ✅ **RULED 2026-08-23: no extension, and the passphrase envelope is the
   at-rest control.** Measured while ruling it, and it inverts the item's
   significance: the four legacy fields are encrypted with `selfEncryptionKey`,
   which `file_io.dart` reads out of **the same document** (`:187`–`:194`) and
   `at_keys.dart` writes into it in the clear (`:1014`). Anyone holding the file
   holds the key, so legacy self-encryption is obfuscation rather than
   protection — the typed section is not missing anything real. Extending it
   would change the at-rest format and buy nothing. ⚠️ **The honest residual:
   the passphrase envelope is optional**, so an unprotected keyfile exposes
   legacy and typed material alike. That is the same for both halves and is the
   thing worth strengthening if anything is.

9. ~~**The one-live-enrollment invariant does not hold when the enrollment id
   is absent.**~~ **FIXED 2026-08-13.** "Have I seen one" is now tracked apart
   from which one it was, and the diagnostic says `no enrollment id` rather
   than naming null. Four rows in `assurance_test.dart`, and reverting the
   guard turns exactly the two null-id ones red while the both-named one stays
   green. Original finding: `AtKeysAssurance.validateKeyMaterials`
   (`assurance.dart:134-161`) uses one variable, `activeAuthEnrollment`, as
   both the id it has seen and the flag for *whether* it has seen one — so the
   guard is `if (activeAuthEnrollment != null)`. `enrollmentId` is parsed with
   `optionalString` (`atkey_material.dart:250`) and the field is `String?`, so
   a material may legitimately carry none; a first active
   `privateAuthentication` with a null id therefore leaves the guard armed with
   null and the **second one does not throw**. That breaks the document-wide
   rule the same method's own dartdoc states — "a second active authentication
   key is a corrupt keyfile whatever algorithm it names" — and it is the rule
   `AtKeys.activeEnrollmentId` relies on for its answer to be unique, which is
   the whole argument for deriving that rather than storing it
   ([`decisions.md` 91.3](decisions.md#913-the-rulings) ruling 5). The fix is to
   track "have I seen one" separately from the id. Verified by reading the
   mechanism 2026-08-13; it wants a differential test whose two arms are a null
   id and a present one.

10. **⚠️ UNEXPLAINED: one functional run lost 26 tests to missing PKAM keys,
    and the mechanism was never found.** 2026-08-13, over
    [14.18](#1418-the-remaining-d1-initial-development-sequence) step 12
    against `at_virtual_env:local`: run 1 was `+115 -26`, every failure
    `@alice🛠` → `privatekey:at_pkam_publickey does not exist in keystore`,
    across sync/notify/put files that the change under test does not touch.
    Run 2, same tree, same runner: **146/146** with zero such errors.

    **What was measured, so it is not re-measured.** `pkam.sh` is
    `sleep 25; install_PKAM_Keys`, and the install itself takes **0.17s** for
    all 40 atSigns with no retry. `@alice🛠` is installed *before*
    `@sitaram🛠` (`.490007` vs `.490549`), so waiting on sitaram is if
    anything the later signal — the "it watches the wrong atSign" theory is
    **wrong**. Both runs' setup phases were byte-identical (26s, sitaram
    found). `install_PKAM_Keys` covers alice; the four atSigns it reports no
    success for are `@srie`, `@sachin` (the CRAM-onboardable pair, by design)
    and `@cloudvm2`, `@device2`. Nothing in `/apps/logs/pkam.log` logs a
    failure — a skip and a success are indistinguishable there except by
    absence.

    **What was done anyway,** because it is a real weakness independent of
    this run: `runLocal.sh` now polls pkamLoad's own log until every atSign
    the suite authenticates as has its key, and refuses to start otherwise.
    The previous gate proved one atSign had one record, and `public:publickey`
    is not the record authentication needs. **This is not known to prevent the
    failure above** — it makes the next occurrence present as a named setup
    refusal instead of 26 red tests pointing away from the cause.

    Treat a recurrence as a live question, not a known flake: **one red run in
    three** is a rate, and nobody has bounded it.

11. **An APKAM rotation that lands and is not persisted locks the enrollment
    out permanently.** `AtEnrollment.update` can move an enrollment onto a new
    authentication keypair (step 16), and nothing in at_auth writes that
    keypair to a keyfile. PKAM verification is record-authoritative, so the
    moment the atServer accepts the update, the only key that can authenticate
    as that enrollment is one that exists solely in the caller's memory —
    and the enrollment id is unrecoverable, because `metadata.keyPackage` is
    written by the creating `enroll:request` and never again.

    Not a defect in step 16, which built the verb caller it was scoped to, and
    not something to "fix" by having the updater persist: the request has no
    keyfile and no atSign, `read` → mutate → `write` against a keyfile is a
    lost update (`WrittenAtKeysIo.update` exists for exactly this), and the
    ordering question — persist before the round trip and risk a keyfile
    naming a key the server refused, or after and risk the reverse — is a
    decision, not an implementation detail. **The only caller that changes
    `apkamPublicKey` today is a test.** Whoever writes the first real one
    (step 20's programme pair drives a rotation mid-run) settles the ordering
    and owns the persistence; the dartdoc on
    `EnrollmentUpdateRequest.apkamPublicKey` says so where they will be
    standing.

    ⚠️ **Read both paragraphs of this item together — they are about different things, and a cold reader took them as contradicting.** The first is about the persistence CODE (unmoved); the second is about the ORDERING (ruled). ⚠️ **Still true after step 20's first landing, 2026-08-14.** The pair that
    landed drives the data path and the stage matrix; its rotation arm is
    deliberately not built, precisely because building it means settling this
    first. So this item did not move, and the sentence above still names its
    owner rather than describing something done.

    ✅ **The ordering is ruled and its first half has landed, 2026-08-14**
    ([`decisions.md` 97](decisions.md#97-a-keyfile-status-a-build-has-never-seen-is-read-not-refused-2026-08-14)).
    gkc chose **two-phase**: the new keypair is filed as *staged* before the
    round trip and promoted to active only when the atServer accepts it, so a
    crash at either point is survivable. Asking for a staging status is what
    exposed the blocker underneath — `CryptographicMaterialStatus` was an `enum` whose parse
    threw, and **at_auth 3.3.0 on pub.dev ships the same three values**, so any
    new status made a keyfile unreadable to every released build *in its
    entirety*. gkc chose reader-first over accepting that break, and the
    tolerant reader is now in: status is an open `String` that round-trips
    unmodified, with the forward order stated as `CryptographicMaterialStatus.rankOf`.

    **What is still owed, in order:** an at_auth release carrying that reader;
    then the `pending` value; then the rotation arm itself.

    ⛔ **The "wait for the fleet" gate is CLOSED, 2026-08-23.** This paragraph
    ended "the staged value is deliberately **not** added yet — a writer may
    emit one only once the fleet is running a build that can read it", and that
    was written when the status enum was the only incompatibility. Two things
    retired it, both measured:

    - **The two keyfile formats are disjoint for every file that exists.**
      at_auth 3.3.0's `fromJson` dispatches on `version`: absent → the legacy
      path, which never looks at `keys`; present and `== 1` → `keys` is
      required, else `AtKeysParseException('Expected array at keys')`. at_auth
      4.0.0's `toJson` emits no `version` when there is no typed material, and
      `version: 1` with `atsignKeys`/`enrollments` and **no top-level `keys`**
      when there is. So dropping a legacy `keys: []` is harmless precisely
      because no `version` is emitted beside it, and a released reader stays on
      its legacy path.
    - **The one reachable conflict has never occurred.** It needs a 4.0.0
      typed write into a keyfile a 3.3.0 app also opens — and **no production
      `.atKeys` file or keychain entry holds any PQ key material** (gkc,
      2026-08-23). With no holder outside this tree, the compatibility
      argument is void.

    ⚠️ **Do not attribute the tolerant reader to
    [14.49.1](#14491-keyentrystatus-becomes-a-typed-string-wrapper--done-2026-08-22).**
    That section converts `KeyEntryStatus`, the *advertised record* status, and
    says in terms that the refusal-based justification does not transfer to it:
    its problem was **lossy** tolerance, not refusal. The tolerant *keyfile*
    reader this item depends on is `CryptographicMaterialStatus`, converted
    earlier and typed by `c81bf045c`.

    The `_apsk` and metadata arms carry no such hazard — neither changes what
    authenticates — which is why the advertisement path step 18 needs is
    usable as it stands.

12. ~~**No at_onboarding_cli app can set any posture flag**~~ — **FIXED
    2026-08-18.** `AtOnboardingPreference` now declares a forwarding
    constructor taking `posture`, `disallowLegacyEncryption`, `signingRollout`
    and `dataSigningKeyAlgorithms` as `super.` parameters, so the whole CLI fleet
    can set them; every parameter is optional and the superclass supplies each
    default, so `AtOnboardingPreference()` means what it always did. Only the
    construction-final flags are forwarded — the mutable fields beside them
    stay assignable and are not repeated. **Proven by the mutation that is the
    plausible wrong fix**: a constructor that takes the same arguments and
    drops them reddens two of the four rows, and the no-arg compatibility row
    correctly stays green. ⚠️ **`SigningAlgoType` is still not exported from
    at_client's barrel (item 13)**, so an app naming that one flag imports
    at_chops directly. What it used to say: "`AtOnboardingPreference extends
    AtClientPreference` and declares **no constructor**
    (`at_onboarding_cli/lib/src/util/at_onboarding_preference.dart:6`), so it
    inherits the implicit no-arg one and every construction-final flag —
    `posture`, `disallowLegacyEncryption`, and now `dataSigningKeyAlgorithms`
    (step 17) — takes its default with no way to pass another. The mutable
    fields beside them (`crypto`, `seedNamespaceKeys`) are assignable and
    unaffected; it is exactly the flags that are final at construction, and
    they are final for a reason worth keeping.

    Noticed while landing step 17, and **not introduced by it** — the same
    was true of `disallowLegacyEncryption` from the day it landed. Every
    `at_cli_commons` consumer is downstream of this: at_talk, sshnoports,
    noports-tools, at_demos, ogentic. The fix is a forwarding constructor,
    which is a small deliberate diff on a published package rather than
    something to fold into another step's commit.

13. ~~**`SigningAlgoType` is not reachable from at_client's barrel, so naming
    an in-use signing algorithm needs a second import.**~~ **REOPENED AND FIXED
    2026-08-18**, by the precedent this item itself named: show-narrowed onto
    the barrel exactly as `EnrollmentKeyExchangeMode` is.

    ⚠️ **This item was recorded as examined-and-deliberately-left, and that is
    a decision, not an oversight — it was reversed because its premise changed
    on the day, not because the next reader disagreed with it.** What changed:
    item 12 shipped, so `AtOnboardingPreference` now takes
    `dataSigningKeyAlgorithms` and the population that must name the type grew
    from at_client apps to the whole CLI fleet. The at_cli_commons README
    gained a line telling consumers to import at_chops for it, which is the
    wart made visible. And the "new inconsistency" argument below is weaker
    than it read: of the two knobs it cites, `signingAlgoType` is
    **deprecated** and `retrofitAuthenticationAlgo` is a derived getter on
    `PqPosture`, not something an app sets — while
    `AtClientImpl.signingAlgoType` is a public getter **returning** the type,
    so a caller was already handed a value it could not name.

    Pinned in `public_api_surface_test.dart`, which imports at_client and
    nothing else; removing the export stops that file compiling, reproducing
    the item's own 2026-08-13 probe. The exported-file golden moved in the same
    commit, which is the review. What it used to say: "An app writing
    `AtClientPreference(dataSigningKeyAlgorithms: {SigningAlgoType.mldsa65})` must
    import `package:at_chops/at_chops.dart` as well as at_client. Verified by
    probe 2026-08-13: a test importing only `package:at_client/at_client.dart`
    fails to compile on the name.

    **Left as is, deliberately**, and recorded so the next reader does not
    re-derive it as a defect: the two SigningAlgoType-valued knobs already on
    the preference — the deprecated `signingAlgoType` and
    `PqPosture.retrofitAuthenticationAlgo` (named `retrofitSigningAlgo`
    until row B1) — have always required that import, so
    exporting it now would be a new inconsistency rather than a fix, and a
    barrel export is public surface that cannot be withdrawn. `SigningRollout`,
    the axis an app is more likely to name, **is** reachable (it lives in
    `pq_posture.dart`, which the barrel exports). If this is revisited,
    the precedent is `EnrollmentKeyExchangeMode`, show-narrowed onto the barrel
    for exactly this discoverability argument
    ([`decisions.md` 70](decisions.md#70-workstream-a-capstone-pqposture-the-five-flags-as-one-value-2026-08-10)).

14. **⚠️ NOT PQ — parked here because this project has no other checked-in
    owed-work list.** 16 prose uses of the banned "atProtocol" spelling
    (it is **"Atsign Protocol"**, capital A, capital P, space-separated)
    survive outside `docs/projects/pq/`, which is clean. Found by the
    2026-08-14 docs sweep and deliberately not fixed then: they sit in six
    packages that session never touched, so folding them into a PQ commit
    would have made the diff cross-package for a spelling change.

    Re-derive the list — do not trust this count, it is a measurement from one
    moment:

    ```bash
    grep -rn "atProtocol" --include="*.md" --include="*.dart" . \
      | grep -v untracked | grep -vE "atProtocol[A-Z]|atProtocol/"
    ```

    Known homes: `at_policy`, `at_rpc`, `at_commons` (`at_key.dart` dartdocs),
    `at_cli_commons` (an example), `at_client` (`at_client_telemetry.dart`,
    a test comment) and `docs/projects/wasm/plan.md`.

    ⚠️ **A further 5 occurrences are IDENTIFIERS, not prose** —
    `atProtocolEmitted`, `AtServerEvent.atProtocolCategory`, and the
    `atProtocol/1.0` wire value. The filter above excludes them deliberately:
    renaming those is a breaking API/wire change, not a docs fix.

15. ~~**An enrolled enrollment's `_apsk` has THREE writers, not one — and a
    dartdoc said otherwise while row B4 was being built on it.**~~ **CLOSED —
    and the strike was owed since 2026-08-15.** The body below has ended "This
    item is CLOSED" since then; only the heading was never struck, so the
    open-item count kept counting it. Found by a cold read 2026-08-17.

    ⚠️ **And its resolution has since been superseded in the reader's favour.**
    Ruling 102 accepted the multi-writer window as documented-and-healing. On
    2026-08-17 [14.32](#1432-a-primary-clients-ml-dsa-signing-key-is-not-visible-to-its-verifiers)
    re-opened that ruling deliberately, measured the window actually costing a
    clobber — four writes to `_apsk.primary` ending on bare RSA — and closed it
    in code by serialising the in-process writers
    ([102.2](decisions.md#1022-the-in-process-window-is-closed-by-serialising-the-writers-2026-08-17)).
    So the plurality is still three, but the race it created is gone.

    Raised 2026-08-14, deferred deliberately, and recorded here because it
    lives nowhere else.

    `SigningKeyMinting._publish` sends `enroll:update` and its dartdoc said
    *"the atServer is the only writer of an enrollment's `_apsk` — one writer
    for the record's whole life, which is what makes a rotation atomic from
    every reader's view"*. `ApkamSigning.publishPublicSigningKey` writes the
    record **directly**, with `atClient.put`, and two production call sites
    reach it for an enrolled client:

    ```bash
    grep -rn "publishPublicSigningKey()" packages/at_client/lib
    # key_package_registration.dart:302  (KeyPackageRegistration.register)
    # published_nskey_key_ring.dart:391
    ```

    The false sentence is corrected in place. **What is NOT established, and
    must not be written down as if it were:** whether the plurality costs
    anything. Both direct writers compose through `publicSigningKeyValue`, so
    they agree with the `enroll:update` path on *content*; and
    `apsk_server_side_test.dart` already proves the atServer permits an
    enrollment to write its own `_apsk` (that is the control arm of the
    cross-enrollment refusal). So the observed facts are "three writers" and "a
    doc claimed one" — not "a race", which nothing here measures.

    Worth an examination rather than a fix: the question to answer first is
    whether any of the three can publish a *different* composition than the
    others, since a rotation that is atomic only when one writer runs is a
    property nobody has stated, let alone tested.

    ✅ **THE EXAMINATION RAN 2026-08-15. The answer is yes — narrowly at rest,
    and sharply inside one window.** Measured with a throwaway probe over
    `signing_key_minting_test.dart`'s harness (built, run, deleted), which
    captured what W2 would compose at each point of a mint and compared it
    against the value the record ends up holding, composed the way the
    atServer does it (`enroll_verb_handler.dart:977-985`).

    - **At rest the two agree** for `{rsa2048}` from nothing, `{mldsa65}` from
      nothing, and the `rsa2048` → `mldsa65` stage transition: byte-identical.
    - **The one at-rest divergence is ORDER, and it is benign.** With two
      retired generations of one algorithm, W1 lists the just-retiring key
      ahead of the keyfile's retired set while the keyfile selector
      (`retiredSigningKeysFor`, now `withdrawnSigningKeysFor`)
      sorts by algorithm only, so within an algorithm it returns slot order.
      Same kids, same pubs, same statuses; readers select by algorithm across
      every entry, so nothing mis-verifies. It costs one extra write — W2's
      `published == value` check fails, W2 rewrites in its own order, and it
      settles, because W1 does not republish at rest (`:146` returns early
      when nothing is missing or superseded).
    - ⚠️ **Inside the publish-before-file window the concurrent writer does
      not write "the old advertisement". It writes the APKAM AUTHENTICATION
      key.** `_publish` runs before anything is filed, so `heldSigningKeys` is
      still empty and `apskEntries` takes its auth-key fallback
      (`apsk_composition.dart:58-61`). Measured: a PQ-native enrollment's
      ML-DSA array replaced by a **bare RSA string** — which also inverts the
      bare-versus-array form rule `bareApskValueOf` exists to protect. In the
      stage-transition case the record ends up naming the OUTGOING key as
      active with the newly minted one absent.

    **Reachability is NOT measured, and the bootstrap alone cannot do it.**
    `PqClientBootstrap` awaits its steps in order and `_collectConveyedKeys`
    — the only in-package `register()`, hence the only in-package W2 trigger
    on that path — runs *before* `_mintInUseSigningKeys`. An interleaving
    needs an application call racing the **unawaited** `startup()` at
    `at_client_impl.dart:623`, and both W2 triggers are publicly exported
    (`AtClientSecretSharing.register`, and `NskeyRotation` reaching
    `PublishedNskeyKeyRing:391`). So the compositions are measured; the race
    is a hypothesis.

    **And it heals.** W2 composes from the keyfile, so its next invocation
    publishes the correct value, and `register()` → `publishPublicSigningKey`
    runs on every start. Verification reads the record live, so envelopes
    signed during the window verify again once it heals. The exposure is one
    process lifetime of refused envelopes and refused key-package
    verification — not permanent unverifiability, which is what this item
    feared.

    ⚠️ **Three things this item's own framing got wrong, corrected here
    rather than silently:**
    1. **W1 does not compose purely from handed-in arguments** — its retired
       half is read from the keyfile at `signing_key_minting.dart:260`,
       exactly as W2's is. That mix, in-memory active half plus keyfile
       retired half, is precisely what makes the order case diverge; a
       purely-handed-in W1 would not have.
    2. **There are FOUR producers, not three.** The atServer writes the record
       at approval from what the enrollee sent on `enroll:request`
       (`enroll_verb_handler.dart:1013-1019`), and W1's own no-enrollment arm
       delegates to W2 with an explicit value (`signing_key_minting.dart:266`).
    3. **`heldSigningKeys`' `canSignEnvelopeWith` filter is not a divergence
       source**, though it looks like one beside W1's in-use-set filter:
       `AtClientPreference` already runs the in-use set through
       `_signableOrRefuse` on the same predicate, so the set cannot name an
       algorithm the filter would drop.

    ⚠️ **RULED 2026-08-15, NOT BUILT —
    [`decisions.md` 102](decisions.md#102-an-_apsk-fallback-value-never-replaces-a-real-advertisement-2026-08-15).**
    gkc chose "the fallback never replaces a real advertisement" over the
    other three options. **Three implementations were attempted and the live
    pack refused all three**, each for a different reason: guarding on what
    the client HOLDS is too wide (an enrollment whose `_apsk` the atServer
    wrote at approval also holds no signing key and must republish — 160/165,
    approval conveyance timing out); guarding on the published SHAPE is still
    too wide (a PQ-native enrollment's authentication key is ML-DSA, so its
    ordinary fallback is an array too — 162/165); and guarding on CONTENT,
    the most defensible form, fails on `public:_apsk.primary.a.__e`, a record
    **no single client owns** — every non-enrolled client publishes its own
    key there and overwriting is the norm, so the first client refused leaves
    another's key standing (160/165, the guard firing exactly once to do it).

    ⚠️ **That last failure is worth more than the guard would have been: the
    demotion rule has no meaning on a record with no single owner.** It can be
    stated for an *enrollment's* `_apsk`; it cannot be stated for `primary`.
    Any re-scoping would start there. ✅ **gkc then ruled the window ACCEPTED
    AND DOCUMENTED** (`decisions.md` 102) — the state heals at the next start,
    verification reads the record live, and the mechanism plus the three
    refused guards are written into `SigningKeyMinting._publish`'s dartdoc.
    **This item is CLOSED.**

    ⚠️ **Both arms were run.** The same tree with the guard stashed is
    **165/165**, so the guard is the cause rather than the environment. And
    the first diagnosis of run 2 — *"the guard never fired, so it is not the
    cause"* — was wrong because `logger.warning` sits below what the
    functional log surfaces: the absence was a claim about the log LEVEL, not
    about the code. Raising it to `severe` made the line appear, and it named
    the record in one line.

    ⚠️ **And a unit test read as a mismatch was the specification.**
    `apkam_signing_keys_test.dart`'s *"republishes when the published value is
    not what it holds"* holds NO signing key while its comment talks about
    rotation. Attempt 1 re-fixtured it on that reading; the live pack showed
    the fixture was right. Nothing is left in the tree from any of the three
    attempts — the guard and its tests are reverted — so this entry is the
    only record that they were tried.

16. ~~**`LocalSecondary`'s enrollment cache can never hit, and its write is
    never read.**~~ **FIXED 2026-08-17 — and it was not the cleanup this row
    described.** Both halves are gone: the read that could never hit and the
    write nothing read. gkc ruled the cache should NOT be made to work, for the
    reason this row already gave — a client re-reads the record on every start
    so that a changed grant is noticed.

    ⚠️ **The row's absence claim was about production only, and the tests were
    the other half.** "Nothing anywhere writes the key the read looks for" was
    measured over `local:` occurrences in `lib/`. Ten test blocks write it —
    nine in `apkam_authorization_test.dart`, one in
    `enrollment_service_test.dart` — under the comment *"Insert the enrollment
    info into the local secondary"*. So the read was a **test-only seam**, and
    removing it turned eight tests red. That is what the row could not see: the
    fixture stood for a state production never reaches, so **the fetch-and-parse
    path underneath every one of those authorization checks had never been
    exercised.** The nine now use `LocalSecondary.enrollment`, already declared
    `@visibleForTesting`; the one with a mock remote stubs the real
    `enroll:fetch` instead, which drives the production path for the first time.

    ⚠️ **Three of the nine seeded through a different client than the one under
    test** (`atClient` while the assertions ran on `enrolledAtClient`) and
    passed only because both shared a Hive path on disk. Through the named seam
    that could not have compiled into a silent pass.

    ⚠️ **A second defect, previously unreachable, became reachable the moment
    the cache went.** Both catch arms around the `enroll:fetch` logged at
    `finer` and fell through to `jsonDecode(enrollmentInfoFromServer!)`, so an
    unreachable atServer surfaced as *"Null check operator used on a null
    value"* from a line naming neither the enrollment nor the fetch — with the
    exception that explains it discarded at a level nobody runs at. It now
    throws `AtKeyNotFoundException` naming the enrollment id and the cause.
    Three tests in `local_secondary_test.dart` cover the no-id, the parsed and
    the failed cases; the "before" behaviour was observed directly, as the
    original eight failures.
17. ~~**`Enrollment.metadata`'s dartdoc claims a field `enroll:fetch` does not
    return.**~~ **FIXED 2026-08-17.** Re-verified against at_server's own source
    at `c6ed3771` rather than inherited: `_fetchEnrollmentInfoById` returns
    exactly `{appName, deviceName, namespace, encryptedAPKAMSymmetricKey,
    status}`, with no `metadata`. The row guessed the field "is presumably
    populated on a different response (`enroll:list`)" — that is right, and
    there is a second: `enrollment_manager.dart:354` returns
    `{enrollmentId, access, apkamPubKey, metadata}` for `enroll:listns`, for
    every approved enrollment in a namespace. The dartdoc now names all three
    verbs and warns that a fetch result carries null. `Enrollment.namespace`
    now documents that it is singular in name and holds the whole grants map.
18. ~~**`MintLock` releases a lock it may no longer own — raised 2026-08-15,
    while building [14.22](#1422-making-the-signing-root-rotatable--decisions-101)
    row 6.**~~ **CLOSED 2026-08-16 — the release itself is gone; see the ✅
    below.** `_release` force-deleted the lock key unconditionally, so a holder
    that overran the ttl deletes whatever lock is there — including a
    *successor's*, freshly taken by another enrollment. A third enrollment can
    then take it and mint concurrently with the second, and mutual exclusion
    breaks between clients that are all obeying the protocol. `_take` already
    writes a timestamp that would serve as a fencing token and nothing reads
    it. ⚠️ **This is pre-existing and it is not the root's**: the same class
    guarded nskey minting and rotation as `NskeyMintLock` before row 6
    generalised it, so any fix changes rotation behaviour and needs its own
    reasoning and its own differential test. What makes it tolerable rather
    than urgent is the same thing that covers the ttl window —
    `reconcileHeldPrivate` on every start retires a private the record does
    not advertise, so the loser heals — and that argument is about the ROOT.
    Whether the nskey path has an equivalent is **not measured**.
    ✅ **MEASURED 2026-08-16, and the item got SMALLER rather than larger.**
    The nskey path does heal a loser, by a different move —
    `NskeySeeding.requestMissingPrivates` *requests* the advertised
    generation's private rather than retiring an unadvertised one, which is
    right because an nskey private is selected by the kid in the envelope being
    opened and so a losing generation is inert. Details and the table are in
    [decisions 104.2](decisions.md#1042-both-paths-already-heal-a-loser--by-different-moves).
    ✅ **CLOSED 2026-08-16 — it disappeared rather than being fixed.**
    [14.24](#1424-the-nskey-mint-elects-a-winner--decisions-105) row 3 removed
    `MintLock._release` outright, so there is no delete to steal and no fencing
    token to build. `withLock` now refuses a lock key with no ttl instead,
    because with nothing deleting the record a missing ttl means it is never
    released at all.
    ⚠️ **Do not rebuild the fence.** A nonce-and-read-back release — delete
    only if the lock is still ours — was designed here in full and is *not*
    the answer: the winner not deleting at all is strictly stronger, and
    reintroducing a delete reintroduces this whole class. That the ttl truly
    frees the lock took an atServer fix
    ([decisions 104.9](decisions.md#1049-the-ttl-does-not-free-the-lock--an-atserver-defect)
    and [104.10](decisions.md#10410-fixed-in-at_server-and-merged)); a client
    relying on ttl-only release is correct **only** against an atServer running
    it, which today means `at_virtual_env:local` and not `virtualenv:vip`.
19. ~~**`tests/at_onboarding_cli_functional_tests` analyzes with 6 warnings, all
    in one file nobody touched.**~~ **FIXED 2026-08-17 — the package now
    analyzes exit 0 (14 info), where it exited 2.**

    ⚠️ **The row read as an import tidy-up and the file was entirely dead.**
    `ecc_secure_element_mock_test.dart` had `void main(){}` — empty — with its
    whole test body commented out beneath it, and its three helper functions
    duplicated in `at_onboarding_cli_test.dart`, which declares its own
    `getPreferences`. The imports were unused because *the test was*. Deleted,
    together with `utils/at_chops_secure_element_mock.dart`, which nothing else
    imported. `utils/onboarding_service_impl_override.dart` stays — the live
    test uses it.

    The secure-element reference is not lost with it:
    `packages/at_chops/example/zariot/at_chops_secure_element.dart` is a live
    example of the same thing, and git history holds the disabled test.

    Re-derive: `cd tests/at_onboarding_cli_functional_tests && dart analyze test`.
20. **`PqSigningRoot` and `PublishedNskeyKeyRing` both take a constructor
    parameter whose TYPE the barrel does not export — examined 2026-08-15 and
    deliberately left.** `PqSigningRoot(atClient, {keysIo, MintLock? mintLock})`
    is exported through `crypto.dart`; `MintLock` is not, so a caller outside
    the package cannot name the argument. Row 6 added the second instance of a
    shape `PublishedNskeyKeyRing` already had (`NskeyMintLock? mintLock`), and
    `crypto.dart`'s own comment records the same class of miss being fixed for
    `NskeyKeyRing`. **Left as is** because both parameters exist for tests, the
    surface is `@experimental`, and widening the barrel is a public-API
    decision rather than a tidy-up. Recorded so it is not re-derived as a
    defect, and so that whoever DOES widen the barrel finds both sites at once.

21. **`publishOwnRootLink` now costs one extra atServer read per start for a
    root-private holder — accepted 2026-08-15, recorded so it is not
    rediscovered as a regression.** Its guard changed from "is a root link
    present" to "does the root link still hold"
    ([decisions 103.5](decisions.md#1035-the-re-anchor-this-forced-which-the-row-did-not-name)),
    and answering the second question means reading
    `public:pq_signing_root@<atSign>` through `_rootCandidates`. It is
    proportionate — the same method already spends a privilege round trip and
    an `_apsk` read before reaching it, and only enrollments holding the root
    private get that far — but it is a real added cost and it was chosen, not
    overlooked. If it ever matters, the fix is to cache the advertised roots
    for the life of the start rather than to go back to a presence check.

22. ~~**`decisions.md` carries one broken intra-document anchor,
    `#1-subsystem-a-…`.**~~ ⛔ **STRUCK 2026-08-17 — it is a FALSE POSITIVE and
    there is nothing to fix.** The only occurrence sits inside a backtick code
    span at `detail/decisions.md:7718`, where the surrounding bullet quotes
    `design.md`'s table-of-contents *as an example* of a label beside a link.
    GFM does not render links inside code spans, so it is not a link and no
    heading needs to match it — and the bullet it lives in already says that
    case was "left alone" deliberately.

    ⚠️ **This is the second time an anchor checker that does not skip code
    spans has produced a finding here.** The first reported 785 checked / 235
    broken across `docs/projects/pq/`; the real number was zero, and the one
    surviving hit was this same backtick block. A checker over Markdown must
    skip code spans and prove a positive control before any absence or any
    count it reports is worth acting on.

23. ~~A released `version: 1` keyfile holding an empty `keys` array is now
    refused, and nobody has named a holder.~~ ✅ **CLOSED 2026-08-23** —
    `1242cb779`/`1242cb879` narrowed the refusal to a **non-empty** array; an
    empty one is accepted and dropped, and an empty one is exactly what
    at_auth 3.3.0 writes on any flush. The holder question is moot either way:
    **no production keyfile or keychain entry holds any PQ key material**
    (gkc, 2026-08-23). The original text follows. `AtKeys.fromJson` throws on
    `containsKey('keys')` since `cb3848b4d` (2026-08-14), empty array included,
    and the refusal is deliberate and well-reasoned — parsing one would leave
    the document reading as untyped and authenticate as the *legacy*
    enrollment while the live enrollment's credentials sat unread beside it.
    at_auth **3.3.0** is published and writes that shape on any flush.

    So the question is not whether the refusal is right; it is **who holds such
    a file**. Ruling 91.4's release table asserted such keyfiles "exist in the
    wild and must be read" and named no holder, which is the shape of argument
    that is void without one — and the cell has been corrected to say the code
    refuses them. If a holder exists outside this tree the refusal is a
    migration owed; if none does, the row was always hypothetical and the
    refusal costs nothing. **Find the holder or retire the concern**; do not
    build a migration on the strength of the sentence that has now been
    removed. at_auth carries `@experimental` on **zero** files, so the
    substrate licence that covers at_client's secret-sharing code does not
    cover this.

24. ~~**A ring built from an `AtClient` alone still does not ask for a private
    it is missing.**~~ **FIXED 2026-08-18, hours after it was raised, under
    [`decisions.md` 111](decisions.md#111-a-key-ring-files-where-its-client-files-2026-08-18).**
    111 derived the `NskeyPrivateFiling`; the ask stayed null unless a caller
    supplied it, so an app that hand-built a ring and installed it as its
    `CryptoConfig` silently lost ruling 38's read-miss self-heal — quieter than
    before 111 rather than smaller, since the ring minted, filed and read
    correctly and nothing looked wrong until a record arrived ahead of its key.
    A ring with a filing now derives the ask as well, lazily on the miss:
    `AtClientSecretSharing.forClient` is Expando-cached per client, so the
    derived ask uses the **same** substrate instance the bootstrap holds rather
    than a rival. The two callers share one body,
    `requestAndFileNskeyPrivate`, so the bootstrap's heal and the derived one
    cannot diverge. What the bootstrap still supplies and nothing derives is
    the **gate** — only it knows `PqStartupGates.askOnReadMiss`. Pinned by
    `asksOnReadMiss` in `nskey_self_heal_test.dart`, with the control that a
    client holding no key source still asks nothing, because an answer with
    nowhere to land repairs the client at its next start and reads meanwhile
    as a heal that ran and did nothing.

25. ~~**`NskeyPrivateFiling`'s readers answer "not held" for every failure,
    including an unreadable keyfile.**~~ **RULED AND FIXED 2026-08-18** —
    [`decisions.md` 112](decisions.md#112-an-unreadable-key-source-is-not-an-empty-one-2026-08-18).
    The split is three ways, not two, and case 1 needed at_auth's new
    `AtKeysSourceAbsentException` to be nameable at all. `readAll` still
    tolerates a failure, deliberately, because its caller builds the client.
    ⚠️ **The first pass of the fix was incomplete and the new test caught it**:
    lifting the source read out was not enough while each reader's own `catch`
    still stood around it. What it used to say: `read`, `readSeed`, `readAll` and
    `readAllFor` each wrap the `keysIo.read` in a `try` whose `catch` logs at
    `finer` and returns null or `const {}`. A keyfile that is corrupt,
    truncated, locked by another process or encrypted under a passphrase this
    client was not given is therefore indistinguishable from one that simply
    holds no private for the generation asked about — and at `finer` the
    difference is invisible in every pack, since the functional runner sets the
    root level to `info` at best. The caller above turns it into
    `NskeyPrivateUnavailableException`, which since 14.30 **parks** the
    notification waiting for a filing that can never arrive, so a keyfile
    problem now presents as a message that is merely late.
    ⚠️ Raised 2026-08-18 while tracing two e2e failures whose symptom was
    exactly this shape, and left deliberately rather than fixed: telling a
    genuine absence from a failure needs a decision about what a reader should
    DO with the second, and a read path's error handler must not repair
    anything. The likely shape is to keep answering null for "no such entry"
    and let an I/O or decode failure propagate, with `readAll`'s
    construction-time caller given an explicit tolerant wrapper — but that
    changes what a client does at start, so it wants a ruling first.

26. **The plan-status guards read only the first five lines of a section, so a
    status stated lower down is invisible to them.** Both guards added
    2026-08-18 to `docs_structure_test.dart` — TODO-row-vs-done-body and
    DONE-row-vs-partial-body — take `.skip(1).take(5)` of the section under the
    heading. That is deliberate: a finished section's later prose routinely
    recounts what used to be owed, and reading further produces false
    positives. But it means a section whose status sits below the window is not
    checked at all. **Measured the same day**: 14.15 sat in TODO for eight days
    with its single item struck; its body opened with a *condition* ("No PR
    opens until … One thing must still be true by then:") and the done marker
    was on roughly the seventh line, so the guard passed it. It was found by
    hand, deriving the remaining-D1 sequence for a summary.

    Two candidate fixes, neither obviously right: widen the window and accept
    false positives, or require every `### 14.x` section to OPEN with a status
    line and check that instead — which is a convention change across ~30
    sections and would want a ruling. Recorded so the guards' coverage is not
    mistaken for completeness.

27. ~~**Seven broken links in this doc set, all pre-dating 2026-08-18.**~~
    **FIXED — re-derived 2026-08-19 and the doc set is clean:** 687 file
    targets across the eight PQ docs all resolve, and 1078 `#anchor`s all land
    on a heading, the last of them (`detail/` pointing at 14.17's live heading
    as though it were local) repaired with 14.38's doc commit. Both controls
    behaved — a known-good target and anchor resolved, a fabricated one did
    not — and the three surviving `](design.md)`-shaped strings in
    `detail/implementation-plan.md` are inside backtick code spans in the
    paragraph describing this very fix, which is the case the original item
    warned about. ⚠️ **The first checker written for this reported 67 broken
    and was wrong**: its slug function preserved em-dashes where GitHub strips
    them, and its positive control passed only because the anchor it chose had
    none. Draw the control from a heading that carries the character the
    checker mishandles. The original finding follows.

    Found by resolving every `](target)` across the eight PQ docs and
    attributing each against the previous commit, so none of these came from
    the `0x01` removal. `detail/implementation-plan.md` linked `design.md`,
    `acceptance.md` and `roadmap.md` as siblings when they are one level up —
    the `../` was missing — plus three dangling `#anchors` there, and one in
    `detail/decisions.md`.
    Re-derive rather than trusting this count: resolve each link target and each
    `#anchor` against the headings of the file it lands in, skipping fenced code
    blocks and the literal `](target#anchor)` that appears in prose as an
    example. ⚠️ **The Markdown anchor hook only fires on the Edit tool**, so a
    doc edited through a script or a shell heredoc is never checked — which is
    how a dangling anchor reached a commit the same day.
28. **`pqSealDefaultVersion` may not deserve to exist.** It moved from `0x01` to
    `0x02` when `0x01` was retired, because deleting a public const from
    at_chops is a wider API decision than that change needed. Nothing reads it:
    `pqSealToBase64` makes `version` required and both call sites pass a
    negotiated value. The argument for deleting it and making `version` required
    on `pqSeal`/`pqOpen` is the one `info` already carries in its own dartdoc —
    "a default is what made it reachable by saying nothing" — and it is sharper
    here, because `0x02` and `0x03` differ by KEM, so a wrong default is an
    unopenable record rather than a downgrade. Offered to gkc 2026-08-18 and not
    taken; raise it whenever at_chops next opens for an API change.
29. **`provenIn` cannot catch a rename it is not the citation for.** It asserts
    `source.contains("'$testName")` for its `testName` argument only; the
    `proves:` prose is documentation and is matched against nothing. Two
    scenarios named live tests solely in that prose
    (`a3_self_data_test.dart`, `a4_shared_data_test.dart`), so renaming those
    tests broke nothing and went unnoticed until a hand sweep. Either stop
    naming tests in `proves:`, or extend the check to quoted names inside it.
    ⚠️ Worth deciding rather than drifting: the doc above `provenIn` promises
    "rename or delete the live test and this goes red", which is true of the
    argument and false of the prose, so the doc currently over-claims.

30. ~~⛔ THE PLAN CONTRADICTS ITSELF ABOUT THE atSERVER IMAGE GATE, and the two
    halves point opposite ways.~~ ✅ **CLOSED 2026-08-23 by measurement, no
    ruling needed.** Half B's premise — "CI uses vip" — is false: the workflow
    sets `atsigncompany/virtualenv:dev_env` at both the functional and e2e
    jobs, and `runLocal.sh` defaults to `at_virtual_env:local`. The gate half B
    served is the one that move settled. Half A's ruling stands, because it
    agrees with where CI actually went. The original text follows. The re-derivation block in the live plan says
    the gate "is gkc's call and is **NOT** to be checked against
    `atsigncompany/virtualenv:vip` (ruled 2026-08-13)". SS-2's entry in this
    file says the opposite — "**Before SS-2 opens a PR**, confirm vip has been
    promoted and re-run the pack against it". One forbids the measurement the
    other requires. ⚠️ **This matters more than its size**: 14.18 row 1 is
    blocked on that gate, it is the last thing standing between here and the
    end of D1 initial development, and a session reading only the second half
    will run a check a ruling forbids. Wants a ruling from gkc, then whichever
    half is wrong amended in place with what it used to say. Evidence that
    prompted it: at_server's ML-DSA PKAM verification landed `648fe9fe`
    (2026-08-11), `git tag --contains` gives `c3.16.0`/`c3.16.1`, and Docker
    Hub reports `virtualenv:vip` `last_updated` 2026-08-15 — which suggests the
    gate may already be liftable, but says nothing about whether checking it
    that way is permitted.
31. **`detail/` carries two stale copies of the `deprecated_member_use`
    count.** Both read `340 at_client`, superseded by the 345 measured
    2026-08-18 and recorded in the live file's two homes. They sit in the
    demoted former plan, so they may be historical by design rather than
    wrong — decide which, and if historical, date them. The general shape is
    what to take from this: **that count now has at least four homes**, and a
    correction that updates the two you have open leaves the others asserting
    the old figure with equal confidence.

32. ~~**`SyncIsolateManager` is dead code, and it holds the last two
    identity-less `RemoteSecondary` constructions in at_client.**~~ **DONE
    2026-08-19** — deleted. Every premise re-derived first and all held: zero
    references outside its own file, absent from every barrel, and the only
    `dart:isolate` import in at_client (now zero, proven with a `dart:convert`
    positive control on the same recipe). The one surviving construction
    outside `RemoteSecondary` itself is `sync_service_impl.dart`, which passes
    `enrollmentId` and `signingAlgoType` — so the "last identity-less" claim
    was exact. ⚠️ **The re-derivation command the item gave was too narrow:**
    `git grep -n 'SyncIsolateManager'` misses `docs/projects/wasm/plan.md`,
    which names the *file* three times and never the class. Those three
    references were the deletion's own schedule (phase 3 and item I9); all
    three are updated. Grep the literal, not only the symbol. The class is
    itself `@Deprecated`, is exported from no barrel, and has zero references
    outside its own file — including tests and examples. The `SyncManager` its
    deprecation message names as its only user no longer exists in the tree,
    `Isolate.spawn` appears nowhere in at_client, and the only doc that
    mentions it is the WASM port plan, which references it three times solely
    to schedule its deletion. Its two `RemoteSecondary(atSign, preference,
    privateKey: privateKey)` calls pass neither an enrollment id nor a signing
    algorithm; after [14.38](#1438-activate_cli-cannot-administer-a-pq-native-atsign)
    change 2 they are the only ones left in the package, so a future audit of
    that shape finds them and has to re-derive that they are unreachable.
    Straight delete. Re-derive: `git grep -n 'SyncIsolateManager'`.

33. ~~**`lib/src/activate_cli/activate_cli.dart` is a deprecated file with no
    caller.**~~ **DONE 2026-08-19** — deleted. ⚠️ **But "no caller" was FALSE,
    and the item's own re-derivation command could not have discovered it:**
    `git grep` searches this repo, and the callers are in other ones.
    `~/dev/atsign` holds two, both importing the library through its private
    path — `atGettingStarted/at_dart/bin/at_activate.dart` (last commit
    2023-07-20, pins `at_onboarding_cli: ^1.3.0`, which resolves to 1.17.0) and
    a checkout of the same file under `karol/at_demos`. Each is a four-line
    `main` that calls `activate_cli.main(args)` and nothing else.

    Deleted anyway, for reasons that survive the correction: all three of its
    top-level members were `@Deprecated('Use auth_cli')`, it is exported from
    no barrel, and reaching it requires importing `package:at_onboarding_cli/`
    **`src/`** — a path Dart convention marks as not-public, so the breakage is
    a compile error at a private import rather than a silent behaviour change.
    The replacement is the `at_activate` binary those files were re-implementing
    by hand. The removal is named in the CHANGELOG so a consumer who hits it
    finds the reason. **Owed, in another repo:** `atGettingStarted` needs its
    `bin/at_activate.dart` pointed at `auth_cli`, or deleting in favour of the
    shipped binary — see the note under [14.19](#1419-small-items-raised-2026-08-12-and-not-yet-acted-on).

    The rest of the original item stands. Its bare `AtOnboardingPreference()`
    at the top of `wrappedMain` was why a grep for posture-less preference
    construction in at_onboarding_cli still returned a hit after 14.38 threaded
    the posture through `createAtClient`. `git grep -nP 'AtOnboardingPreference\(\)'
    -- packages/at_onboarding_cli/lib packages/at_onboarding_cli/bin` now
    returns **three** hits and no defect: the deliberate `posture == null`
    branch of `AuthCliArgs.preferenceUnder`, and two mentions in
    `at_onboarding_preference.dart`'s own dartdoc. Not zero — do not "fix"
    them.

34. **The stream-transfer pair is deprecated for v4, has no in-repo caller,
    and cannot be used from outside either.** `AtClient.stream()` and
    `sendStreamAck` are both `@Deprecated("Obsolete, will be removed in v4")`;
    nothing in this repo calls either, and the receive half
    (`StreamNotificationHandler`, which drives `stream:receive`/`stream:done`
    over its own socket) is reachable only from `sendStreamAck`, so it is dead
    by the same argument. `AtStreamResponse` and `AtStreamStatus` are exported
    from no barrel, so an external consumer can call `stream()` but cannot
    write down the type it returns. The deprecation was never announced in the
    CHANGELOG. It belongs on the v4 removal list rather than being carried as
    a live API — and until then it stays covered by
    `AtClientImpl.buildRemoteSecondary`, which is the only reason it now
    authenticates as the client it belongs to.

35. **Lands in `atGettingStarted`, not here: `at_dart/bin/at_activate.dart`
    imports a file this repo deleted.** Found 2026-08-19 while doing item 33,
    by grepping `~/dev/atsign` rather than this repo — which is the only reason
    it was found at all. It does
    `import 'package:at_onboarding_cli/src/activate_cli/activate_cli.dart'`
    and calls `activate_cli.main(args)`; that library is gone as of
    at_onboarding_cli 1.17.0, and the pubspec's `^1.3.0` will resolve straight
    into the break. A checkout under `karol/at_demos` holds the same file.
    The fix is to delete the wrapper and use the shipped `at_activate` binary,
    which is what it was re-implementing. Not urgent — the repo's last commit
    is 2023-07-20 — but it is a real consumer, and recording it here is the
    only thing stopping the next reader concluding the deletion had no
    downstream at all.

    ⚠️ **The general lesson is worth more than the item.** Item 33 read "no
    caller" and gave `git grep` as its re-derivation. Both were written from
    inside this repo, and a `git grep` *cannot* see a consumer in another one,
    so the command would have confirmed the claim forever. Any absence claim
    about a **published package's** API needs a search whose scope is wider
    than the repo that publishes it.

36. ⛔ **D1 GATE (gkc, 2026-08-23). Three clauses of UC-A2.5/UC-A2.6 are
    asserted by the catalogue and NOT proven by the live rows that cite them.** Recorded 2026-08-19 when both
    rows went `PROVEN`, because the alternative — marking them proven and
    saying nothing — is the overclaim the catalogue exists to prevent. The
    scenarios in `packages/at_client/test/acceptance/a2_enrollment_test.dart`
    carry a `⛔ NOT proven` note naming this item, so a reader meets it where
    the claim is made rather than here.
    1. **A superseded kpid's envelope still opens.** The live row proves the
       *gaining* case, where the original key stays active. The swap case —
       retire X-Wing, mint ML-KEM — is unit-proven (the private half is
       retained, status `retired`) but no live row seals a secret to the old
       address before the amendment and opens it after.
    2. **A peer negotiates to whichever key its own `sealsToKeyAlgorithms`
       order prefers.** Needs a second atSign sealing to the amended package.
    3. **UC-A2.6's state gate — the same request against a REVOKED
       enrollment.** The two refusals proven live are the foreign-enrollment
       and owner-connection arms.
    Each needs a secret in flight or a revocation, which is why they were not
    folded into the first pass. Re-derive:
    `git grep -n "NOT proven" -- packages/at_client/test/acceptance/`.

#### 14.19.1 Things that LOOK like defects and are not

⛔ **Moved to [ruling 116](../decisions.md) on 2026-08-23. Do not restore this
copy.** It had diverged from the live plan's copy of the same section — this one
carried items 0-6, the live one 0-8, and they differed by 68 lines. The two
entries missing here were the most recent, including one whose own text says it
"will look obvious again". That divergence is why the list now has a single
home.

### 14.20 Building rulings 98 and 99 — the sequence

[`decisions.md` 98](decisions.md#98-rollout-1-moves-the-authentication-key-not-the-signing-key-2026-08-14)
and [99](decisions.md#99-the-keyfile-groups-by-enrollment-and-the-atsigns-own-keys-move-out-2026-08-14)
say **what** and **why**. This says **in what order**, because several of the
orderings are the difference between a working rollout and a broken fleet.

✅ **EVERY row of 14.20 is built and 14.20 owes NOTHING.** Rows A1, A2, A3,
B2, B1, B3, B4, B5, C1 and D2 landed 2026-08-14; C2 landed 2026-08-15 in
`e74a68ce2`; **D1's tail closed 2026-08-15** — `signingAlgo` now says plainly
that it names the *authentication* key's algorithm, on all **three** at_commons
declarations rather than the one the row named. (This banner read "Still unbuilt: C2, D1's tail" until
2026-08-15, while the C2 row below it already said DONE. **Third time a summary
line here has outlived the rows it summarises** — when a row moves, grep this
section for the banner rather than editing only the row.)

A rollout-1 enrollment — created by a retrofit or by a PQ-native activation —
now owns an RSA-2048 signing key **before it submits**, advertises that key
bare in `_apsk`, files it, and signs its key package with it. A released
at_client 3.14.0 reader has been measured parsing that advertisement. A client
moving on to rollout 2 mints its ML-DSA signing key and **retires** the RSA
one, which stays advertised as `retired` so that what it signed — including
that key package — still verifies.

Both traps this section used to arm have **fired and been discharged**; they
are kept below as the record of what they cost, not as live warnings.

Until A1 landed this section read "nothing below is built, the code implements
NONE of rulings 98 or 99", which was true of the whole of 99 as well.

**The concrete target shapes are `keyfile-target-rollout1.json` and
`keyfile-target-rollout2.json` beside this file** — tracked, so a fresh clone
has them. **Match their STRUCTURE exactly**: field names, nesting, which entry
sits where, keyId grammar, `status` on every part. The *values* are elided
placeholders (`"<392 chars>"`, `"<the apkam app name>"`) and are not literals to
reproduce.

#### The seven shapes this sequence does not decide — all ruled 2026-08-14

These were six open questions, each deciding a shape that a wrong guess builds
silently. A seventh surfaced when they were checked against the tree. **All
seven are now ruled, in [`decisions.md` 100](decisions.md#100-the-seven-shapes-ruling-99-left-open-2026-08-14),
which carries the measurement behind each.** Summarised here because they are
what row A1 encodes:

1. **`AtKeys`' accessors split by scope** — `getKey`, `keysForKeyId`,
   `retireKey` and `replaceKey` become enrollment-scoped and take the
   enrollment beside the keyId; a separate family addresses `atsignKeys[]`.
   All six production call sites outside at_auth are atSign-scope and move to
   that family.
2. **The caller supplies "the enrollment I authenticate as"**, and `AtKeys`
   stops deriving it implicitly. `activeEnrollmentId` has no production caller,
   and both live resolvers already pass an explicit id. ⚠️ Amended the same
   day: a cold start has no id to supply, so `AtKeys` offers
   `enrollmentIds` / `authenticatableEnrollmentIds` /
   `resolveAuthenticatingEnrollment()` — invoked by name, throwing rather than
   picking when several qualify.
3. **`apkam:<enrollmentId>:<n>` becomes `auth:<algo>:<gen>`**, with no
   read-side tolerance for the old grammar — nothing released ever wrote a
   typed keyfile, and row A3 deletes the generated ones.
4. **The generation IS the slot** — `root:<algo>:<n>`, next generation
   highest-plus-one, `.2`/`.3` overflow gone. The frozen `pq_signing_root`
   literal is the *record* name and does not move.
5. **`namespaces`/`appName`/`deviceName` come from the enrollment request**
   where one exists and are omitted where none does; C2 fills them at the
   first authenticated start. No placeholders.
6. **`operations` is unchanged** — parsed, round-tripped, emitted when
   non-empty.
7. **An nskey private lives in `atsignKeys[]`** (the seventh). It is filed
   with no enrollment id today, which is ruling 3's signal for atSign-owned
   material. ⚠️ Not a general rule about KEM material: the enrollment's key
   package keypair stays in the enrollment.

#### Why this order

The container before its contents: 99 reshapes `AtKeys`, and 98's writer
changes file *into* that shape, so doing 98 first means writing the same code
twice. Within each, the reader before the writer.

| # | Work | Why here |
|---|------|----------|
| A1 | ✅ **DONE 2026-08-14.** `CryptographicMaterial`/`AtKeys` parse+encode moved to `enrollments[]` and `atsignKeys[]`; keyIds normalise to `<role>:<algo>:<gen>` and drop the embedded enrollment id; `status` stays explicit; `CryptographicMaterial` keeps `enrollmentId` in memory, populated from the container. The accessors split by scope per [`decisions.md` 100](decisions.md#100-the-seven-shapes-ruling-99-left-open-2026-08-14) ruling 2 — every one of the six production call sites outside at_auth was atSign-scope. `activeEnrollmentId` is gone, replaced by `enrollmentIds` / `authenticatableEnrollmentIds` / `resolveAuthenticatingEnrollment()`, which throws rather than picking when several qualify. **Two things the suites caught that reading did not:** the key-package pairing collected public halves document-wide, so under `(enrollment, keyId)` one enrollment's published address could vouch for another's private half; and an rsa2048 retrofit files under `auth:rsa2048:1`, which a blanket rename to `auth:mldsa65:1` got wrong. A `version: 1` document carrying a top-level `keys` is now refused **by name** — a judgement this row made, not a ruling: `keys` is no longer reserved, so parsing one would sweep its material into `metadata` and authenticate from the flat block as the legacy enrollment. Rails: at_auth **298/298**, at_client **1265** (2 skipped), acceptance **57** (2 skipped), at_onboarding_cli **39/39** | Everything else files material. This is the container |
| A2 | ✅ **DONE 2026-08-14.** The single-active-authentication rule moved from `validateKeyMaterials` (read) to a new `AtKeysAssurance.refuseSecondLiveEnrollment` (write), which only `AtKeys.addKey` calls. **The rule had to be moved, not deleted, and the reason the reader inherited it is worth keeping:** `fromJson` built the document by calling `addKey` for every material, so read and write validation were literally the same code path. A private `AtKeys._parsed` now files through `_file` — the structural invariants without the write-only policy. The refusal also got stricter where it moved: it is owner-agnostic and algorithm-agnostic, so one enrollment holding `auth:rsa2048:1` and `auth:mldsa65:1` both active is refused, which the per-(role, algorithm) rule structurally cannot see. Pinned in `plural_enrollments_test.dart` — reads, round-trips both enrollments on flush, refuses to name one, serves a caller that names its own, and the write path still refuses. **Proven by mutation**: making `_parsed` file through `addKey` again turns exactly the four read-tolerance tests red and leaves the writer-refusal test green. Rails: at_auth **304/304**, at_client **1265** (2 skipped) | Reader-first. A reader that refuses a second entry makes plurality unenableable later — the `.single` lesson |
| A3 | ✅ **DONE 2026-08-14.** Seven generated keyfiles carrying the old typed shape were deleted from `tests/at_functional_test/test/testData/` (`@colin`, `@jeremy`, `@xavier`, `rf2b-legacy`, `rf2b-t1`, `rf2b-t5`, `rf2d-posture`); all seven were untracked and regenerable. **The correction below held exactly**: the two tracked fixtures, `@alice🛠_key.atKeys` and `@bob🛠_key.atKeys`, are legacy-flat with no `version` at all and parse unchanged. ⚠️ **Corrected 2026-08-14:** an earlier draft of this row said the *tracked* fixtures are version-1 old-typed and become unreadable. They are not — and `build_test_atkeys.dart` files no typed material. Only keyfiles a *live retrofit* produced carry the old typed shape, and those are generated, not tracked. ⚠️ **All seven are back on disk, and that is the proof rather than a regression**: the functional run that followed regenerated them in the NEW shape (`version: 1`, `enrollments[1]`, no top-level `keys`), which is the container being written and read by production code against a real atServer |
| B2 | ✅ **DONE 2026-08-14 — and it moved ahead of B1, see the note below this table.** `apskEntries` now advertises the active signers plus the enrollment's **retired signing keys**, and the APKAM authentication key only while it *is* the signer — never retained. A new `AtKeys.retiredSigningKeysFor` supplies the retired entries **public-only** (a retired key must never sign again) and does **not** require the private half to still be present, so a build that wipes withdrawn private material cannot silently withdraw the advertisement with it. Selected on exactly `CryptographicMaterialStatus.retired`: `dead` was never adopted, and an unknown status is skipped rather than guessed at. ⚠️ **The last of those was reversed on 2026-08-22** — the method is now `withdrawnSigningKeysFor`, selects on not-active-and-not-`dead`, and carries the keyfile's token out with each key; skipping an unknown status withdrew the key from a record that is rewritten whole, and the open `KeyEntryStatus` removed the reason for it ([14.49.1](#14491-keyentrystatus-becomes-a-typed-string-wrapper--done-2026-08-22)). Reached through a new `ApkamSigning.retiredSigningKeys` (now `withdrawnSigningKeys`), which — unlike `heldSigningKeys` — is **not** filtered by `canSignEnvelopeWith`, since these entries exist for *other* parties to verify with and dropping one on a fact about the publisher would unverify its envelopes for every reader that could have handled them. `SigningKeyMinting._publish` re-reads them rather than assuming none, because that publish rewrites the whole record. **Proven by two symmetric mutations**: gutting `retiredSigningKeysFor` to empty reddens exactly the two retained-signing-key tests, and removing the dedup reddens exactly the third. Rails: at_auth **304/304**, at_client **1268** (2 skipped), acceptance **57** (2 skipped), functional **163/163** — the last one being the only thing that could say a live advertisement still reads | Must precede any writer that mints a signing key, or rollout 1 publishes an array |
| B1 | ✅ **DONE 2026-08-14, together with D2 — see below.** `SigningRollout` gained `defaultRetrofitAuthenticationAlgo` (`now` → `rsa2048`, `rollout1`/`rollout2` → `mldsa65`) and its in-use sets became `{}` / `{rsa2048}` / `{mldsa65}`. `retrofitSigningAlgo` is renamed `retrofitAuthenticationAlgo` **and is now a derived getter**, so both named constructors lost an argument — [98](decisions.md#98-rollout-1-moves-the-authentication-key-not-the-signing-key-2026-08-14) ruling 6, "two stored fields would be two controls over one position". **One defect this surfaced:** `selfRetrofit` read `preference.posture.retrofitSigningAlgo`, i.e. the *posture's* stage, so an app setting `signingRollout: rollout1` beside a migration posture would have retrofitted under `now`'s algorithm and said nothing. It now reads `preference.signingRollout`, which is the effective stage. Rails: at_client **1269** (2 skipped), functional **163/163** | 98's stages are defined here. Everything downstream reads them |
| B3 | ✅ **DONE 2026-08-14, both halves.** `selfRetrofit` mints a fresh RSA-2048 signing keypair before submitting and hands it to both the request and the key-package builder; at_auth advertises it as `apskLegacy` (bare), files it under `sign:rsa2048:1`, and signs the key package with it per [98.3's amendment](decisions.md#983-where-the-signing-key-comes-from). The seam is an explicit `EnrollmentRequest.advertisedSigningKey`, supplied by the caller because holding a signing key is a rollout position and at_auth cannot see a preference; absent, every path behaves as before, which is what keeps `now` unmoved. `SigningRollout.mintsOwnSigningKey` derives from the in-use set being non-empty rather than being listed again. **The greenfield-onboard half followed the same shape**: `makeActivationPqNative` mints the rsa2048 signing keypair, sets it on `AtOnboardingRequest.advertisedSigningKey` **and** hands the same pair to the key-package builder; `AtAuthImpl` carries it into `FirstEnrollmentRequest` and files it after the atServer assigns an id. **Proven by six mutations in all, each reddening only its own tests**: in the retrofit half, ignoring the advertised key in `_apskFor`, dropping the filing, and signing the package with the APKAM key; in the onboard half, dropping the request field, which reddens all three onboard pins. Rails: at_auth **307**, at_client **1273** (2 skipped), functional **163/163** | ⚠️ **B3 is one commit, not two.** Splitting it publishes an ML-DSA array at enrollment creation — the breakage rollout 1 exists to prevent, landing on peers who cannot fix it |
| B4 | ✅ **DONE 2026-08-14.** The role is recorded on `SigningKeyMinting` itself — what reaches it is an enrollment created before enrollment-time minting, or a client whose in-use set has changed since the last start — and the defect this row was carrying is fixed. **The defect, measured rather than read before it was fixed:** the heal path always published the **array**, because `_publish` sent `EnrollmentUpdateRequest(signingKeys: …)` with no branch and `EnrollmentUpdater` prefers `signingKeys` over `apskLegacy`. A rollout-1 client healing a pre-B3 enrollment therefore advertised a one-entry JSON array where [98.1](decisions.md#981-the-stages) requires the bare RSA string every deployed consumer base64-decodes — the breakage rollout 1 exists to prevent, arriving from the second writer while the first one obeyed the rule. The bare-versus-array rule now has **one** definition, `bareApskValueOf`, and the enrolled path uses it to choose which *field* carries the advertisement. Pinned in both directions: a mutation making everything bare reddens 7 rows, and the row for the bare form was written first and watched fail. ⚠️ **Whether the atServer honours `apskLegacy` on an `enroll:update` was a claim about the server, not the client** — it had only ever been sent on the enrolment request — so it is measured live in `tests/at_functional_test/test/apsk_server_side_test.dart`, "a healed enrollment advertises its signing key in the bare form", which drives the real writer and reads the record back with a control proving the enrollment held no signing key beforehand | Follows B3 |
| B5 | ✅ **DONE 2026-08-14.** `SigningKeyMinting.mintMissing` became `reconcileSigningKeys`: it computes *held − wanted* beside *wanted − held*, publishes the post-move advertisement, files the addition and then the withdrawal, and returns both lists. New `AtKeys.retireSigningKeys(enrollmentId, algorithm)` moves both halves to `retired`, selected on the `sign:<algo>:<n>` shape rather than the `privateSigning` role — the role is shared by the atSign's signing root and by any other material an enrollment signs with. **Three orderings the row did not name, each found by asking what it routes into:** the publish must be *handed* the keys being retired, because the keyfile still holds them as active at that point and a re-read would drop them from the advertisement entirely rather than move them to `retired`; the withdrawal is filed *after* the addition, or there is a moment with no active signing key where `signingKeys` falls back to an authentication key the advertisement has stopped naming; and an empty in-use set retires **nothing**, since that is the released posture rather than "every algorithm has left the set". **The stage-transition test the row asked for is `signing_key_minting_test.dart`, group "a stage transition"** — eight rows, including an envelope signed at rollout 1 that must still verify against the rollout-2 advertisement, run on the no-enrollment arm so the pin reads the `_apsk` value this client actually published. **Proven by three mutations, each reddening only its own rows**: dropping the retirement (5 red), publishing without the retiring keys (2 red, one of them the envelope, failing with "no algorithm in common"), and restoring the old early return on an empty *missing* set (1 red). A fourth, in at_auth, dropped the keyId shape filter and reddened exactly the row about it — ⚠️ **after a first attempt at that row was itself red for a fixture reason**: it gave one enrollment two active `privateSigning` keys of one algorithm, which `addKey` refuses, so the mutation "reddened the right test" while proving nothing. Rails: at_auth **312**, at_client **1281** (2 skipped), acceptance **57** (2), at_onboarding_cli **39** | Required before rollout 1 → 2 works at all; not required for rollout 1 |
| C1 | ✅ **DONE 2026-08-14.** Asking for a client that already exists with a preference naming different rollout axes throws an `ArgumentError` naming **every** differing axis, through one static `AtClientImpl.refuseChangedRolloutAxes` and a new `AtClientPreference.rolloutDifferencesFrom`. ⚠️ **The row named one site and there are THREE** (this said "two" until the wrap-up, which is the count-not-the-list trap again — the third was appended in the sentence below instead of correcting the headline): `AtClientManager.setCurrentAtSign` short-circuits a same-atSign call carrying no override argument and returns **without calling `create` at all**, which is the ordinary path — so a guard on the cache alone would have been loud only where a caller happens to pass an `atKeysIo`/`atLookUp`/`enrollmentId`, and silent everywhere else. All three check; three mutations, one per site, prove none stands in for another. **Two shapes the ruling did not state, both found by the caller sweep before writing the guard:** the comparison is by **value**, never identity — the e2e pack builds a fresh preference for every `setCurrentAtSign`, so an identity test would refuse every one of them — and the **posture is compared by what it means**, not as an object, since `PqPosture` declares no `==` and only `const` instances are canonicalized, so `PqPosture.legacy` written without `const` would be refused over a difference that does not exist. Rails: at_client **1297** (2 skipped), functional **164/164**. ⚠️ *This row said **1296** until the wrap-up: that figure was written before the `setPreferences` door was built, and never re-measured after it. 1281 (B5) + 1 (B4's bare-form row) + 15 (this row's new file) = 1297, which is what two runs at `aa9f5ea55` printed.* ⚠️ **A third door was found and gkc ruled it shut the same day:** `AtClient.setPreferences` replaces the whole preference on a running client, so leaving it unchecked would have made the other two a check in appearance only. Naming the replacement does not make the change possible — the substrate reads these axes at a startup that has already run, so accepting them would leave the client *reporting* a stage it never applied, which is worse than the silent drop, where the caller at least kept the stage it was running under. Everything outside the rollout axes is still replaced. One call site in the tree (`tests/at_functional_test`'s `TestUtils`, which passes the object it just built), so the live pack measures it on every init | Independent of A and B; can land any time. Do it early — it is what makes a mis-wired stage loud instead of silent |
| C2 | ✅ **DONE 2026-08-15.** `PqClientBootstrap._reconcileEnrollmentSnapshot`, a new **last** step — nothing reads the snapshot, so it can only delay a step that heals key material, never enable one — writing through `WrittenAtKeysIo.update`. ⚠️ **The row's scope was one guard short, and it is the guard that matters: the snapshot is recorded only for an enrollment the keyfile ALREADY HOLDS.** `recordEnrollmentSnapshot` creates the slot when it is missing, and `AtKeys.toJson`'s `hasTypedContent` is `_enrollments.isNotEmpty \|\| _atSignMaterialsByKeyId.isNotEmpty` — so reconciling an enrollment with no material rewrites a legacy-flat keyfile as a `version: 1` document purely as a side effect of having opened it, which is the one thing that serializer's own comment exists to prevent. [decisions 100](decisions.md#100-the-seven-shapes-ruling-99-left-open-2026-08-14) ruling 6 asks C2 to *fill* snapshots, not convert keyfiles. **It shares `LocalSecondary`'s memoised fetch rather than issuing its own `enroll:fetch`** — one record described by two readers is two chances to disagree, and the record was already being read on the authorization path. A non-String grant value is **skipped, not stringified**: `'42'` recorded as an access level reads as a grant. A changed `namespaces` logs at `warning`, but only when there was a previous value to differ from — the first fill on a retrofit's keyfile is not a change, and logging it as one cries wolf on every such file. **Proven by mutation: disabling the slot guard reddens exactly one row of 14.** Rails: at_client **1302** (2 skipped), functional **164/164**, analyze exit 0 | ⚠️ Must use the store's atomic verb. This tree has already lost key material to two unawaited start-time writers doing read-mutate-write on this file. **Read from at_server `6a86fbcc` — do not re-derive:** `enroll:fetch` returns `{appName, deviceName, namespace, encryptedAPKAMSymmetricKey, status}`, where **`namespace` singular holds the whole `namespaces` MAP**, and a caller may always fetch its own enrollment |
| D1 | ✅ **DONE — the tail closed 2026-08-15.** `SigningRollout.rollout1` ("deliberately identical to `now` in what this client writes") and `selfRetrofit` ("no ML-DSA anywhere") were corrected in B1's commit, along with the two `PqPosture` constructor dartdocs, which carried the same claim in a third form. `signingAlgo` now states that it names the **authentication** key's algorithm — the key that signs the `from:` challenge — and not the algorithm the enrollment signs documents with, which is the one thing its name gets wrong. ⚠️ **The row named `EnrollParams` and there are THREE declarations**, which is this row's own right-hand warning coming true: `EnrollVerbBuilder` carried the identical sentence and `PkamVerbBuilder` — the verb where the field can ONLY mean the authentication key — carried none at all. | ⚠️ `design.md` carried the same errors and was banner-flagged 2026-08-14 — but a bare copy of the rollout-1 claim survived two paragraphs above the banner until the doc sweep. One correction does not find the others; grep the claim, not the file |
| D2 | ✅ **DONE 2026-08-14, in the same commit as B1 — it had to be.** ⚠️ **This row said "needs B3 to exist first" and that was wrong by two rows: the red arrives at B1**, because B1's in-use set is what starts the minting, and B3 only moves *when* the key is minted. The receiver is now `published` throughout: at_client 3.14.0 fetches the sender's `_apsk` through its own `EnvelopeSigning.getApkamPublicKey` and parses it with `RSAPublicKey.fromString` — the exact call at_chops makes verifying a pkam signature. The scenario reaches that mixin by `src/` import deliberately, because a fetch reimplemented in the harness would test the reimplementation; both arms' `EnvelopeSigning` declares the same three members, checked, since one present in only one build would take the whole matrix down rather than this row. **Two positive controls**, both required: rollout 1's value must DIFFER from `now`'s (or the stage is not applied and the row compares a case with itself — which is what it did until today), and rollout 2's must NOT parse as RSA (or the parse discriminates nothing). Both fired green | Needs B1, not B3. ⚠️ Do not "restore" acceptance.md to match the stale test |

#### The ordering re-check over every remaining row (2026-08-14)

Run after the order had been wrong twice, on gkc's instruction, to stop
finding the next one by building it. **The question each row is asked is not
"what does this define" but "what does this route into".** A row that changes
a default or a set does not announce itself as a writer, and both earlier
misorderings — and the one below — are that same shape.

⛔ **B1 opened a window B3 has to close, and it is open in the tree right
now.** MEASURED, not read: submitting a self-enrollment with
`signingAlgo: mldsa65` builds `apskLegacy: null` and

```json
{"v":1,"keys":[{"kid":"…","use":"sign","alg":"mldsa65","pub":"<the APKAM authentication key>"}]}
```

— the probe confirmed `pub` is byte-identical to `apkamPublicKey`. That is the
exact shape [98.3](decisions.md#983-where-the-signing-key-comes-from) says must
never be published. `_apskFor` (at_auth,
`enrollment_submitter.dart:132`) takes its array branch for anything that is
not `rsa2048`, and B1 made `rollout1` retrofit under `mldsa65` — so a rollout-1
enrollment now advertises an **ML-DSA array naming its authentication key**
from creation until the first client start republishes it via `enroll:update`.
The code path predates B1; what B1 changed is that a rollout-1 preference
routes into it by default, where before it took an explicit argument or the
post-quantum posture (under which the array is correct).

**Consequences for the remaining rows, in the order they should now be built:**

| Order | Row | Why it moved, and what it must not miss |
|---|---|---|
| 1 | **B3** | ⛔ **Urgent, not merely next** — it closes the window above. ⚠️ **It must also re-sign the key package**, per [98.3's 2026-08-14 amendment](decisions.md#983-where-the-signing-key-comes-from): `_apsk` verifies the key package as well as the envelopes, and the package is signed by the APKAM key today, so swapping the record without swapping the signer makes every peer refuse to seal secrets to the enrollment. ⚠️ It must **mint, advertise AND file** the signing key. Advertising without filing leaves the next start's reconciliation (then `mintMissing`, now `reconcileSigningKeys`) finding nothing held, minting a *second* key and republishing — orphaning the key the enrollment record already advertised. ⚠️ It also spans two packages: the mint is at_client (`selfRetrofit`, `pq_native_onboard`) and `_apskFor` is at_auth, so the signing key's public half has to reach the submitter through `AtEnrollmentRequest` |
| 2 | **B5** | ✅ **DONE — see the row above.** ⚠️ **"B5 only has to set the status" was wrong**, and it is the same misread this section is about: the status change routes into the *advertisement*, which is composed before the keyfile has moved. Writing only the status would have withdrawn the key from `_apsk` altogether rather than retiring it there, and taken every envelope it signed — plus the key package rollout 1 signs with it — down with it. It was still invisible to the rails for the reason given: the matrix copies a fresh keyfile per cell, so nothing transitions a client between stages, and the stage-transition test B5 owed is now the only thing anywhere that does |
| 3 | **B4** | ✅ **DONE, and it was not the bookkeeping row it read as.** "No hazard" was wrong: B5 read the heal path in source and found it published a one-entry JSON array where rollout 1 requires the bare RSA string, and building B4 measured that before fixing it. The lesson is the section's own, one level down — a row described by what it *defines* (a changed role) hid what it *routes into* (the second writer of a record deployed peers parse) |
| 4 | **C1** | ✅ **DONE.** "Priority up" was right, and the row was still one site short: the guard belongs on `AtClientManager`'s same-atSign short-circuit as well as on the cache, because the short-circuit never calls `create`. Same lesson again — the row named what it *defines* and missed a path it *routes into* |
| 5 | **C2**, **D1** | ✅ Both done. Genuinely independent of the B rows. B1's commit corrected `SigningRollout.rollout1`, `selfRetrofit` and both posture dartdocs; the `signingAlgo` tail closed 2026-08-15 across all three at_commons declarations |

#### Why B2 moved ahead of B1 (2026-08-14)

⚠️ **This table listed B1 first until 2026-08-14, and that order could not be
built.** B2's own "why here" states the rule — *must precede any writer that
mints a signing key, or rollout 1 publishes an array* — and B1 is what switches
that writer on. The chain, every link read in source before the swap:

`signingRollout: rollout1` → `AtClientPreference` derives
`dataSigningKeyAlgorithms` whenever the caller does not set it
(`at_client_preference.dart:111`) → B1 makes that `{rsa2048}` →
`PqClientBootstrap`'s `mintInUseSigningKeys` gate defaults **true**
(`pq_client_bootstrap.dart:43`) → `mintMissing` (B5 renamed it `reconcileSigningKeys`) returns early only on an empty
set (`signing_key_minting.dart:69`) → it mints an RSA signing key → `_publish`
calls `apskEntries`, which under the pre-B2 rule appends the auth key as
`retired` → two entries → `apskValueOf` emits the **JSON array** that every
deployed reader base64-decodes as an RSA key and fails on.

The matrix's `current/` arm reaches it: it sets `signingRollout` and
deliberately leaves `dataSigningKeyAlgorithms` unset, and attaches a persisting
`FileAtKeysIo`.

The plan author was thinking of B3's enrollment-time writer, which is the one
B4 later demotes to a heal path. **The rule is right and the ordering was
wrong**, so B2 landed first and the window was never created — no measurement
of the breakage was needed, and none was taken. gkc ruled the swap 2026-08-14,
preferring it to landing B1+B2 as one commit.

#### Owed from the A rows

✅ **Discharged 2026-08-14: the functional pack ran 163/163 at `e5dce43b7`**,
the head the A rows left. It had last run at `cb3848b4d`, and A2 (`edc9dc8be`)
changed the code path every keyfile read goes through — "only at_auth
validation" being a claim about scope rather than a measurement.

✅ **B2 was then measured against it: 163/163 again.** B2 changes what `_apsk`
carries, so a live run was the only thing that could say whether the
advertisement still reads — and having the baseline first is what made that
second run mean one row rather than four.

#### Two traps a fresh session will otherwise hit — both now discharged

✅ **The UC-G1.14 trap fired exactly as written, one row earlier than
predicted.** This section said the byte-identity test "must go red once B3
lands". It went red at **B1**, measured: 162 passed, that one failed, and the
two `_apsk` values in the failure output were both bare RSA keys differing from
offset 44 — rollout 1 publishing its signing key where `now` publishes its auth
key, exactly as 98.1 specifies. It was replaced per D2 in B1's own commit
rather than weakened. **The general lesson, twice in one sequence: the row that
switches a behaviour on is the row whose in-use set changes, not the row that
looks like the writer.**

✅ **`retrofitSigningAlgo` was not what its name said**, and B1 renamed it to
`retrofitAuthenticationAlgo`. It selects the **authentication** key's
algorithm, and the wire field it feeds (`EnrollParams.signingAlgo`) has always
meant that too — the wire field keeps its name deliberately (a multi-repo seam
against a released atServer) and only its dartdoc is corrected, which is still
owed by D1.

#### What this does NOT depend on

Rollout 1 needs no APKAM rotation, so none of A, B, C or D waits on
[14.19 item 11](#1419-small-items-raised-2026-08-12-and-not-yet-acted-on)'s
rotation arm or on the at_auth release that arm waits on. Those gate step 20's
remaining half only.

### 14.21 The signing root cannot be rotated — raised 2026-08-15

> **RULED 2026-08-15 the same day — [decisions 101](decisions.md#101-the-signing-root-becomes-an-ordinary-signing-key-and-rotatable-2026-08-15).
> The root becomes an ordinary signing key and D1 makes it rotatable without
> building the rotation.** The rest of this item is the statement of the
> problem, kept because the ruling is only legible against it.
>
> 📌 **CONVENTION, established here 2026-08-15: a section kept deliberately as a
> snapshot still needs a STATUS banner saying which of its items are now
> closed.** "The text below is left as written" preserves the reasoning, which
> is right — but a reader meets the items as a list of live problems, and a
> closed obstacle read as open is how merged work gets rebuilt. Keep the prose,
> date the banner, name the row that closed each item. A cold read of this file
> found exactly that failure here.
>
> ✅ **STATUS 2026-08-15 — obstacles 2 and 3 are CLOSED; do not read them as live
> work.** Obstacle 2 ("verifiers hold exactly one root key") was closed by
> **row 5**: both root-link verifiers now try every advertised root, active and
> retired. Obstacle 3 ("root links carry no key identifier") was closed by the
> same row — the link gained an optional top-level `kid`. Obstacle 1 (the
> record is immutable) is **row 6**, unbuilt. Obstacle 4 (the heal paths treat
> a successor as poison) was closed by **row 4**.
> ⚠️ The symbol `_publicKeyFrom` cited under obstacle 2 no longer exists —
> row 1 deleted it. Re-derive with `git grep _publicKeyFrom -- packages/`
> (zero hits) rather than looking for it.
>
> ⚠️ **One premise below is false, and the ruling overturns it: that records
> already published on live atSigns constrain the design.** They do not.
> Nothing is released, so no client outside this tree mints a root — every
> atSign carrying one is ours, to delete or recycle. *Immutable*, *frozen* and
> *one-way door* describe a constraint on rewriting **one record**, never a
> constraint on choosing the shape. The text below is left as written, because
> the four obstacles it enumerates are what the ruling answers; where it reasons
> from permanence, the ruling is what holds.

The atSign's root signing key is persisted in two places, and only one of them
can ever change.

- **At rest**, in the keyfile's `atsignKeys[]`: keyId `root:mldsa65:<generation>`
  with both halves filed under it as `privateSigning` + `publicVerification`
  materials, each carrying `algorithm`, `createdAt`, `status` and
  `bytes`. It sits in the atSign's own container — `enrollmentId` null — not in
  any enrollment's.
- **Published**, at `public:pq_signing_root@<atSign>`:
  `{"v":1,"keys":[{"alg":"ml-dsa-65","pub":"<base64>"}],"successor":null}`,
  written with `immutable = true` (`nskey_records.dart:101-106`).

**The immutability is deliberate, and it is doing a second job.**
The record is immutable so that several `__manage` apps cannot each find no
root and each mint one, leaving two chains with no way to reconcile them
([decisions 18.2](decisions.md#182-custody));
[decisions 46.5](decisions.md#465-the-signing-root-is-the-only-one-way-door)
records it as "the only one-way door". A dozen comments in
`pq_signing_root.dart` reason *from* "the root never rotates" — the mint path,
the crash-recovery republish, the lost-create retirement and the pull backstop
each cite it. Rotation has to unpick that reasoning and put something else in
place of the create-once race control, not merely add a code path.

**Four concrete obstacles beyond the immutability itself.**

1. **`successor` cannot do the job it was reserved for.** It is stamped `null`
   at mint and nothing reads it — the only hits in the tree are the write site
   and tests asserting it is null. Because the record cannot be rewritten it
   can never be filled in afterwards, so as shaped it is a forward pointer
   writable only at a moment when there is nothing to point at.
   [decisions 18.3](decisions.md#183-shape) reserved it for the revocation
   chain; the slot exists and is unusable where it sits.
2. **Verifiers hold exactly one root key.** `_publicKeyFrom`
   (`pq_signing_root.dart:139-149`) returns the first entry whose `alg` matches
   and stops, so `PqSigningChain._rootPublicKey` and the root-link check behind
   it see one key however many `keys[]` carries. The field was made a list on
   purpose — mint time being the only moment a root can be made verifiable
   under more than one algorithm — and the reader forecloses it. ⚠️ **This one
   carries an ordering property the others do not**, and it is *prospective*
   rather than a compatibility debt. No client in the field reads these records
   today. But any peer verifies against the atSign's root, so once the GA minor
   ships readers that take `keys[0]`, those are what would stop a second entry
   ever being adopted. Widening it is a prerequisite of every scheme and has to
   land before any writer — the deadline is the GA minor, which is why
   [decisions 101](decisions.md#101-the-signing-root-becomes-an-ordinary-signing-key-and-rotatable-2026-08-15)
   ruling 6 puts it in D1.
3. **Root links carry no key identifier.** The shape is
   `{v, alg, payload:{childEnrollmentId, apkamPublicKey}, signature}`
   (`PqSigningChain.linkPayload` / `_rootLinkOver`), so a verifier holding two
   root keys cannot tell which one signed a link and must try each. Workable at
   one or two roots; it is not a selection mechanism, and it is not what a
   revocation would need in order to say *which* root is repudiated.
4. **Three heal paths actively destroy a private that does not match the
   published root.** `reconcileHeldPrivate` retires it (`:525-549`), `file()`
   refuses to file it (`:398-433`), and `store()` drops it (`:359-360`). All
   three are correct today — together they are the repair for a keyfile
   poisoned by a lost create — and all three would treat a *successor* private
   as poison for as long as the record it corresponds to is not the published
   one. A rotation therefore cannot stage its private ahead of its record,
   which is the ordering every other key in this design uses.

**At rest, none of this applies — rotation is already representable there**, so
the problem is the published half and the client code that reads it, not the
keyfile. `atsignKeys[]` files the root as `root:mldsa65:<generation>` with both
halves under one keyId, the generation *is* the slot (retired material is never
removed, so a new private lands beside its predecessor rather than over it),
and at_auth's single-active-per-`(role, algorithm)` rule is **enrollment-scoped
only** — `validateAddKey` requires `candidate.enrollmentId != null`
(`assurance.dart:209-219`) — so two active root generations may legally coexist
in one keyfile today. Two client-side details would still have to move:
`_activePrivate` takes `.firstOrNull` over the active root slots
(`pq_signing_root.dart:629-634`), so an overlap resolves by iteration order
rather than against the published record, and `keyIdPrefix` hardcodes
`mldsa65` (`:70`), so a root under a different algorithm has no slot naming.

**One inherited claim wants a probe before more design rests on it.**
[decisions 46.5](decisions.md#465-the-signing-root-is-the-only-one-way-door)
says "nobody can *replace* one" and calls `successor` the only migration path.
`Metadata.immutable`'s own dartdoc says something weaker: immutable records
**may not be changed** but *can be deleted*, with `force:` on the delete verb
(`at_commons` `lib/src/keystore/at_key.dart:524-526`), and `delete:force:` is
in the grammar (`delete_verb_builder.dart:36`, `syntax.dart:86`). What the
atServer actually does with `delete:force:` against a public immutable record
is **not measured** — one functional probe settles it, and until it is run the
door stays recorded as closed. Even if it opens, delete-and-recreate gives up
the create-once race control the immutability exists for and leaves a window in
which any privileged enrollment's `mintIfAbsent` mints a fresh root, so it is a
mechanism to be designed rather than an escape hatch to be used.

**What is deliberately not settled here.** Whether the root should rotate at
all, and by what mechanism — delete-and-recreate, a successor record under a
second name, or a reserve key published as a second `keys[]` entry at mint —
is a ruling nobody has made. This is recorded as one item rather than five so
the obstacles are read together: fixing any one of them alone still leaves the
root un-rotatable, and obstacle 1 cannot be fixed in place at all.

**Claimed for D1 as of the ruling.** This paragraph said "not claimed for D1"
when the item was raised, hours before
[decisions 101](decisions.md#101-the-signing-root-becomes-an-ordinary-signing-key-and-rotatable-2026-08-15)
put the rotatability work in scope — the rotation *machinery* is what stays
out. The rows are [14.22](#1422-making-the-signing-root-rotatable--decisions-101).

### 14.22 Making the signing root rotatable — decisions 101

[decisions 101](decisions.md#101-the-signing-root-becomes-an-ordinary-signing-key-and-rotatable-2026-08-15)
rules the shape and the scope; this is the order. **D1 builds rotatability, not
rotation** — row 7 is the boundary, and nothing here mints a successor.

**Two things measured before sequencing**, because rows below would otherwise
rest on them:

- **at_client 3.14.0 has no signing-root reader at all.** Zero matches for
  `pq_signing_root` or `PqSigningRoot` anywhere in its `lib/`, and it ships no
  `lib/src/crypto/nskey/` directory. Positive control: `wrapAndSign` resolves
  to three sites in the same tree, so the search reaches it. `tests/pq_matrix/published/`
  therefore cannot see a root-record change, and no row here owes the matrix a
  cell.
- **NINE test files across THREE separate test packages exercise this
  subsystem**, and row 1 breaks assertions in all three. ⚠️ **This entry said
  "three functional files" until 2026-08-15 and that was WRONG** — it came from
  listing `tests/at_functional_test/test/` for filenames *containing*
  `signing_root`, which finds files **named** for the root rather than files
  that **use** it, and looks in one package of three. Re-derive with, and only
  with:

  ```
  git grep -l "pq_signing_root\|PqSigningRoot" -- 'tests/*'
  ```

  `tests/at_functional_test/`: `pq_signing_root_create_once_test.dart` (asserts
  the create-once property row 6 removes, so it is rewritten rather than
  broken — ⚠️ **row 6 did exactly that and the file is now
  `pq_signing_root_mint_lock_test.dart`**; the `git grep` above is still the
  way to re-derive this list, and it will show the new name),
  `signing_root_pull_test.dart`,
  `signing_root_pull_two_enrollments_test.dart`,
  `enrollment_chain_link_live_test.dart`, `pq_legacy_interop_live_test.dart`,
  `pq_native_onboard_live_test.dart`.
  `tests/at_onboarding_cli_functional_tests/`: `pq_native_onboard_test.dart`.
  `tests/at_end2end_test/test/pq/`: `legacy_server_abort_test.dart`,
  `retrofit_e2e_test.dart`.

  ⚠️ **The `.single['alg']` assertions are the landmine, and they are in two
  packages at_client's own analyze and test cannot see** —
  `pq_native_onboard_live_test.dart:109` and
  `pq_native_onboard_test.dart:113` both assert
  `(rootJson['keys'] as List).single['alg'] == 'ml-dsa-65'`. Row 1 changes that
  spelling to `mldsa65` **and** makes `keys` a list that may hold more than one
  entry, so `.single` is exactly the `.first`-family trap this tree has a
  standing rule about. Four more sites assert the `'ml-dsa-65'` literal
  (`pq_legacy_interop_live_test.dart:141`,
  `pq_native_onboard_live_test.dart:104`,
  `pq_native_onboard_test.dart:106`, and `wire_literal_pins_test.dart:589`,
  which is at_client's own pin on `rootKeyAlgo` — row **1**'s business, not
  row 2's, even though row 2's note is where the pins are discussed).

| # | Row | Why here |
|---|-----|----------|
| 1 | ✅ **DONE 2026-08-15 in `19a31d51b`.** The record carries `{kid, use, alg, pub}` composed by `apskAdvertisement` and read by `apskSigningKeys`; `successor` and the bare-base64 reader are deleted; `rootKeyAlgo` became `SigningAlgoType.mldsa65`, so ML-DSA-65 has ONE wire spelling. ⚠️ **The row did not name what it routes into, and it mattered: `publishedPublicKey` is called from THREE sites in `tests/at_end2end_test`**, invisible to at_client's analyze — so it stays singular and now means *the active root* (well-defined only because this row brings `status`), with `publishedPublicKeys` added beside it, active-first, for row 5's verification. One test was **deleted** rather than updated — "a root published before the shape was settled is still read" asserted the bare reader on the premise that published roots must be tolerated forever, which is the greenfield rule again. Rails: at_client **1301** (2 skipped — one fewer, that deletion), functional **164/164**, analyze exit 0 | First, because every row below addresses entries by `kid` or `status` and neither exists until this lands |
| 2 | ✅ **DONE 2026-08-15.** `keyIdPrefix` became `keyIdRole` + `keyIdPrefixFor(algorithm)`, and the **parse moved down to at_auth**: `AtKeys.isRoleKeyId(keyId, role)` is algorithm-blind and is what `signingKeysFor` already used privately, so the `<role>:<algo>:<generation>` grammar has one home instead of a reader in at_client agreeing with a writer in at_auth by hand. `AtKeys.keyIdPrefix(role, algorithm)` composes it, and at_auth's own five sites now go through it. ⚠️ **The row named three things it routes into and there was a fourth: the three `CryptographicMaterialAlgorithm.mlDsa65` literals on the MATERIAL** in `store` and `_storeFreshPair` — a slot id composed from one vocabulary while the material it holds is filed under another. Both now come from `rootKeyAlgoToken`, pinned against `CryptographicMaterialAlgorithm.mlDsa65`. ⚠️ **And the before-grep understated at_auth: a filtered grep showed one caller of the private parse and an unfiltered one showed three.** Proven by mutation: restoring the algorithm-specific prefix reddens exactly one test, the new one | ⚠️ Routes into `_freeSlot`, `nextAtSignGeneration('root', …)` and the `PqSigningRoot.keyIdPrefix` pin in `wire_literal_pins_test.dart`. That pin is **at-rest** so it moves with the id; the record-*name* pin beside it does not move |
| 3 | ✅ **DONE 2026-08-15.** `_activePrivate` is **deleted** — one name was answering three different questions. `privateHalf` goes through `_signingPrivate`, which returns the active private corresponding to an **active** advertised entry, with the record's entries as the OUTER loop so the record decides and filed order does not. `mintIfAbsent`'s record-absent branch keeps a local `_activePrivates(keys).firstOrNull` because correspondence is undefined there by construction. `_retireUnadvertised` is the one heal both `reconcileHeldPrivate` and the mint now use, and it retires **every** unadvertised private rather than the first. ⚠️ **The record is consulted ONLY when more than one active private is held** — four production sites document `privateHalf` as the cheap local check before a round trip, one of them on the approval path, and a test pins that no `get` is issued in the single-private case. ⚠️ **A test caught a conflation in my first cut**: "no ACTIVE entry" and "no VERIFIABLE entry" are different answers — the first is evidence that nothing signs, the second is no evidence at all. Proven by mutation: restoring `.firstOrNull` reddens exactly the two tests that pin this row. **Original wording and its hazards, kept because they are why the row was rescoped:** `_activePrivate` returns the active private whose public half corresponds to an advertised entry, rather than `.firstOrNull` over the root slots. ⚠️⚠️ **I WROTE "row 4 made exactly one active private an invariant" HERE AND IT WAS FALSE. Verified false 2026-08-15 at source, twice over — and the defect behind it is now FIXED in its own commit, ahead of this row.** (1) `assurance.dart:209-214` refuses a second active of one role+algorithm **only when `candidate.enrollmentId != null`**, and root material is atSign-scope with `enrollmentId == null` — so the store accepts two active root privates and they survive a keyfile round trip. (2) `_storeFreshPair` has **no guard at all**: it computes `_freeSlot` and adds both halves unconditionally. Its only protection is `mintIfAbsent`'s `held == null`, read at `:273` — and `_retireSlot` and `generateKeyPair()` are awaited between that read and the write at `:322`, while `AtClientImpl` fires the PQ bootstrap **unawaited** (`at_client_impl.dart:623`), whose `filePendingPrivate → file → store` files a conveyed private in that window. The claim was true *per `io.update`* and I generalised it across a read-decide-write. **`.firstOrNull` returns the earliest-filed slot** (`_atSignMaterialsByKeyId` is an insertion-ordered `{}`), i.e. the loser of that race. So this row is **not** a demotion. ✅ **The window itself is closed** — the check moved inside `_storeFreshPair`'s own update, proven by a test that stages the interleaving with an `AtKeysIo` that files a conveyed private in the instant before the mint's write opens, and reddened by removing the guard. Leg (1) — the store *accepting* two actives — is unchanged and by design: at_auth carries key material and does not police an atSign's root. ⚠️ **Row 3 as WORDED would break three things** — it disables the poisoned-keyfile heal (`pq_client_bootstrap.dart:281` gates `reconcileHeldPrivate` behind `privateHalf != null`, and a correspondence-aware selector returns null for exactly the private that heal exists to retire), it breaks `mintIfAbsent`'s crash-recovery republish (correspondence is undefined there by construction — that branch runs only when `roots.isEmpty`), and it reddens row 2's `a root slot of another algorithm is still a root slot`, since `publishedRoots` returns `[]` when nothing is published | ⚠️ Four callers ask "do I hold the root" through it — `privateHalf`, `store`'s already-held guard, `requestPrivateIfAbsent`'s cheapest check and `hydrateStore`. With two generations that question has an answer *per entry*, and `.firstOrNull` answers it by iteration order |
| 4 | ✅ **DONE 2026-08-15, and built BEFORE row 3** — gkc ruled that the plan's order was backwards, because "can a successor private exist" is decided here and row 3's selector has nothing real to select between until it does. `publishedRoots` exposes the advertised entries (not just their bytes), all three heals judge against that set, and `_corresponds` takes its algorithm from the entry — the folded gap. `verifiableRootAlgos` now separates what this build can **check** from `rootKeyAlgo`, what it **mints**. `store` gained `supersedingAllBut` and stopped reporting success for a private it dropped. ⚠️ **One premise of mine was wrong and a test caught it: "accept any advertised private" does NOT mean file it.** A retired key's private signs nothing, so a late-arriving predecessor is recognised rather than discarded as poison, and still not filed beside an active successor — a slot for it would be dead material. Proven by two mutations, each reddening exactly one test: judging against `activeOnly` reddens the poison case, and restoring the unconditional `return true` reddens the late-predecessor case | ⚠️ This row decides whether a successor private can exist at all. Today all three paths treat non-correspondence as poison — retire, refuse, drop — so without it a second root private cannot be filed even by hand.<br><br>**MEASURED 2026-08-15, not predicted** — a probe staging a record with an active successor beside a retired predecessor, against a keyfile holding the predecessor. Row 1's reader already passes (`publishedPublicKeys` returns both, active first). Two paths fail: `reconcileHeldPrivate` retires the held predecessor even though the record advertises it, and the conveyance keeps the predecessor while discarding the successor. ⚠️ **My prediction of the second mechanism was WRONG and the measurement is worth more than the guess: I expected `file()` to return false. It returns TRUE and logs "Filed the signing root private" — `store` returns `true` unconditionally once `io.update` completes, whatever its mutate callback decided, so a conveyed key is dropped under a success log.** Re-derive with `dart test test/pq_signing_root_test.dart --concurrency=1` against the `a record advertising a successor beside a retired predecessor` group |
| 5 | ✅ **DONE 2026-08-15, in two commits.** The tolerant reader first (`b6badebf0`), then `kid`. ⚠️ **The row named ONE verifier and there are TWO** — `_checkRootLink` and the conveyance check inside `_publishPendingRootLink`, both resolving through one singular key source; the second refuses to stamp a link it cannot verify, so fixing only the named one would have left a conveyed link rejected while a directly-read one passed, presenting as a verifier bug. ⚠️ **"Signing selects the active root" read as preserved and was OWED**: `file()` filed a private matching only a RETIRED entry as the keyfile's ACTIVE private whenever the keyfile held nothing — `store`'s guard refuses a *second* active, so the rule I wrote in row 4 held only while something active was there to sit beside. Measured by a test written first. ⚠️ **"The fallback keeps links written before this row verifiable" was FALSE as stated** — no such link exists anywhere the rails reach, and one would verify unchanged since nothing on this branch retires a root entry. The mechanism is right and the reason is not: it is for links **other builds** write, and for the peer-signed links the conveyance verifier checks. An unmatched `kid` **fails** rather than falling back, or the field would be decoration. `verifierFor` went public because its dartdoc claimed to be the one place `verifiableRootAlgos` becomes code while `PqSigningChain` built its own verifier at two sites | Needs row 1 for `kid` and row 4 for a second private to exist at all. The fallback is what keeps links written before this row verifiable |
| 6 | ✅ **DONE 2026-08-15.** `pqSigningRootKey` drops `immutable`; the interlock is `_rootlock@<atSign>`, and `NskeyMintLock` became **`MintLock`**, taking the lock's `AtKey` rather than an `(owner, namespace)` pair, so one implementation serves both records. The mint reads the record **twice** — once before the lock so an atSign that already has a root never takes one, and again *under* it, because a winner that published in between is invisible to the first read and a mutable record would let this mint overwrite it. `_publishAndAnchor` became `_publish` and the anchor moved OUTSIDE the lock, leaving the critical section a re-read, a keygen, a keyfile write and one publish. ⚠️ **A refutation caught a regression I had already written:** I dropped the retire on "the write failed and nothing is published", reasoning that a mutable record makes the publish retryable. Nothing retries — `mintIfAbsent` runs at activation and retrofit only, and `pq_client_bootstrap.dart:292` says so in as many words ("a mint is once per keyfile while a start is every time") — so a kept pair would be permanent, would satisfy the pull's cheapest guard so the enrollment never asks, and would get a root link signed with it that `publishOwnRootLink` never rewrites. The retire stands, with that as its stated reason. ⚠️ **Two windows the lock does not close, now stated in the class dartdoc rather than implied:** the ttl can expire mid-critical-section, and `MintLock._release` force-deletes without checking it still owns the lock (pre-existing, and it applies to the nskey lock too — see [14.19](#1419-small-items-raised-2026-08-12-and-not-yet-acted-on) item 18). ⚠️ **The atServer makes `immutable` STICKY** — `at_metadata_builder` preserves `immutable == true` from stored metadata whatever an update asks — so this changes roots minted from here on and one already written with the flag can never be rewritten by anyone. Rails: at_client **1325** (2 skipped), analyze exit 0 | ⚠️ Routed into `_publishAndAnchor`'s entire catch block, as predicted — but ALSO into a live functional test that would have **destroyed shared state**: `pq_signing_root_create_once_test.dart` wrote a second root expecting refusal, and with the record mutable that write LANDS, replacing `@srie`'s root with garbage for every later file in the run. Renamed to `pq_signing_root_mint_lock_test.dart`, and `pq_native_onboard_live_test.dart:117` had the same landmine. Three `provenIn` citations in at_client's own acceptance suite name that file and its test names, so they moved in the same commit. ⚠️⚠️ **AND THE REPLACEMENT REINTRODUCED THE HAZARD IN A SECOND COSTUME, MEASURED NOT PREDICTED: 162/165 with three failures in `enrollment_chain_link_live_test.dart`.** The rewrite stopped writing a second root but kept the old file's *precondition* step — seed a root if none is published — and that seeds one whose private nobody holds. `enrollment_chain_link_live_test.dart` runs after it and MINTS the root into its own keyfile so its approval rows have a private to convey; a root already published makes `mintIfAbsent` stand down, and three of its rows fail with nothing pointing at the file that caused it. Fixed by removing every contact with the root record: the write mode is now proved on a **scratch record carrying the root's own `Metadata`**, written twice, and the loser-of-the-race row **moved into `enrollment_chain_link_live_test.dart`**, which owns the root on that atSign and mints it legitimately. The lesson generalises past this file: **a "precondition" step that CREATES the shared thing is the destructive write, and it does not look like one** |
| 7 | ✅ **DONE 2026-08-15, and it was mostly a test — the row's own caution was right.** Scoped before building, as gkc asked: **every mechanism was already there.** Row 5 had proven the record half (`pq_signing_chain_test.dart`: a link signed under a RETIRED root verifies through both verifiers, a stranger root is broken, a mislabelled kid is broken) and rows 3-4 the keyfile half (`pq_signing_root_test.dart`: a successor conveyed to a holder of the predecessor is filed, the predecessor keeps its slot and bytes but goes `retired`, `privateHalf` returns the successor). What was missing is that they hold **TOGETHER** — each was proven in its own file against its own fixture, and D1's claim is a claim about the composite. `D1 boundary: a keyfile and a record both carrying two root entries` drives both halves in one scenario through the real APIs: the successor arrives over the ordinary filing path, lands in its own slot beside the retired predecessor, signing selects the active root and stamps *its* kid, and the link signed earlier under the retired one still verifies. The two-entry state is written **by hand** — needing a rotation to reach it would be the boundary failing. ⚠️ **It passed on the first run, which proves nothing, so it was isolated by mutation:** filing the successor over its predecessor's slot (`_freeSlot` pinned to generation 1) reddens this row and **nothing else** in the file; making the verifier judge `activeOnly` reddens it with its two row-5 siblings; making the kid read off the first filed public half reddens it with the anchoring group. Also added as the tenth cross-cutting acceptance invariant, which moved `test/acceptance/README.md`'s two pinned counts 53 → 54 — caught by `catalogue_test.dart` going red, which is that build input working. Rails: at_client **1326** (2 skipped), acceptance **58** (2 skipped) | Buildable with no rotation machinery anywhere. It passed, so rotation is a later operation over a structure that already holds — which is the whole claim D1 is making |

**Out of scope, deliberately:** the rotation operation — mint a successor,
publish it, retire the predecessor, re-anchor the enrollments — and revocation.

**The doc sweep each row owes, located now so it is not rediscovered later.**
These read as the contract, so they assert the old shape exactly as a stale
test would — and they are **not** corrected in advance, because until the rows
land they describe what is actually built:

- ✅ **The row-6 sweep RAN 2026-08-15, and the list above was less than half
  of it.** This block named four lines (`design.md:290`/`:323`,
  `acceptance.md:1115`/`:1159`, the last two already off by two after row 1's
  edits). A fan-out over all three test packages and every tracked doc found
  the rest: `design.md` also had `:298` and a whole ten-line
  `pq_signing_root` **lifecycle** paragraph at `:1127` written from create-once,
  and needed a new row in its §1.3 record table; `acceptance.md` also had the
  test-matrix column legend, UC-A1.1's step 3 and Then-clause, UC-B1.1's step
  5, and the section-13 cross-cutting invariant. Outside the docs the sweep is
  what caught the destructive live test and the three `provenIn` citations.
  ⚠️ **Two rules did the work: `acceptance.md` prose inside a row is safe to
  edit and a `###` UC heading is not — UC-B5.3's heading stays, and only its
  Given/When/Then moved — and `test/acceptance/README.md` is a build input
  whose PINNED parts are just its two count regexes, so its narrative was free
  to correct.** Row 1's own leftovers (the record's value shape, still written
  as `{alg: 'ml-dsa-65'} … successor: null` in both contracts) were found by
  the same sweep and fixed in a separate commit, since they were false before
  row 6 rather than because of it.
- `decisions.md` is a ledger and is **amended in place**, not rewritten: 18.3
  and 46.5 already carry pointers to 101.

⚠️ **Apply [14.20](#1420-building-rulings-98-and-99--the-sequence)'s question to
every row before building it:** what does the row *route into*, not what does it
define. On this plan that question has been the answer six times running, and
rows 2, 3, 4 and 6 each carry a routing note found by asking it rather than by
reading the row.

---

### 14.23 Per-generation nskey records — decisions 104, REJECTED

⛔⛔ **REJECTED — DO NOT BUILD THIS.**
[14.24](#1424-the-nskey-mint-elects-a-winner--decisions-105) is what was built
instead, and it is done.
[decisions 104](decisions.md#104-per-generation-nskey-records-rejected-2026-08-16)
was rejected the same day it was written, in favour of
[105](decisions.md#105-the-nskey-mint-elects-a-winner-2026-08-16). This section
is kept in full so the design is not re-derived from scratch, which has already
been attempted once.

⚠️ **Its rows contradict 14.24's on the same lines of code, so following it by
accident is not a no-op.** Row 2 here says the `StateError` at
`published_nskey_key_ring.dart:292` "is deleted" and that a loser with nothing
published "mints anyway"; 14.24 row 4 says it is **rewritten, not deleted** and
that the loser **must not mint**. Row 6 here says 14.19 item 18 is still owed;
14.24 says it disappears. **Where they disagree, 14.24 wins.**
(A context-free reader jumped straight to this heading by anchor and got a
confident, unflagged instruction to build the rejected design. That is why this
banner exists.)

The rest of this section is the order that *would* apply if 104 were revived. Generations get their own records, the
advertisement becomes a summary healed from them, and the mint lock survives on
this path only as an advisory hint. **The signing root is out of scope** and
keeps its dispositive interlock —
[14.19](#1419-small-items-raised-2026-08-12-and-not-yet-acted-on) item 18 is
still owed, and now guards exactly one record with one caller.

**Three things measured before sequencing**, because rows below rest on them:

- **The tolerant reader has already shipped.** `NskeyAdvertisement.keys` is
  genuinely a list and `bestKeyFor` walks it filtering on `status == active`;
  its own dartdoc says *"Not `keys.single`… a reader that assumed one would
  throw on the first advertisement that did"*. So the usual
  reader-ships-first ordering constraint does not apply here. Re-derive:

  ```
  git grep -n "bestKeyFor\|keys.single\|keys.first" -- packages/at_client/lib/src/crypto/nskey/
  ```

- **The summary's wire format does not change at all.** `suites` already
  defaults to `openableSuitesForAll(keys.map((k) => k.alg))` — the union across
  generations — and `NskeyProvider._sealVersionFor` intersects that union with
  the sender's own algorithm's suites, so a multi-generation advertisement is
  safe by construction. `status` is already parsed. What changes is the writer.
- **Nothing mints while an advertisement exists.** `NskeySeeding.seed` is
  `if (await ring.currentPublic(owner, namespace) != null) continue;`. This is
  why the stranded-generation hole is unfixable today and why row 6 can exist
  at all. ⚠️ It also disproves the "a later mint overwrites and cleans up the
  stranded generation" reasoning, which was believed for part of the design
  session — see [decisions 104.3](decisions.md#1043-two-claims-corrected-in-the-course-of-measuring).

**The rows, in order.** Each names the differential that proves it, because
every one of these can pass for the wrong reason.

| # | What | The differential |
|---|---|---|
| 1 | The generation record — composer, first-marker parser, `EnvelopeType` — **plus** the healer **plus** `_mint` writing the record and then healing. ⚠️ **ONE commit.** Splitting it leaves a tree that writes generation records and publishes no advertisement, so every sender sees a cold start; [B3](#8-phase-rb--rollout-rotation-retirement--versioning-r-1-sh-1-b-2-ke-1-b-3-on-1-r-2) had the same shape and had to be one commit for the same reason | two concurrent mints leave **two** generations, both advertised, neither overwritten. Mutation: make the healer replace rather than merge → the second mint's generation is the only one left |
| 2 | The mint lock becomes advisory: a loser re-reads, adopts if a usable generation is published, and **mints anyway if not**. The `StateError` at `published_nskey_key_ring.dart:292` is deleted | lock held **and** nothing published → mints. Today that throws, so the arm is a straight inversion. ⚠️ This is the row that decays — the test is the only thing that stops the advisory contract silently becoming a hard lock again |
| 3 | `status: retired` gains a writer; `rotate` becomes mint + retire; its lock-contention dartdoc is deleted because it documents a failure that can no longer happen | retiring drops the entry from the summary **and** leaves the private filed. Both halves, or it passes for a delete |
| 4 | `_ownCurrent` deleted; the owner's own advertisement goes through the same fetch/verify/TTL path as a peer's | a retirement written by **another** enrollment stops this one sealing to the withdrawn generation. Today it seals to it for the life of the process |
| 5 | `requestMissingPrivates` walks the **log** rather than the summary | a new device pulls a **retired** generation's private — which it needs to open `__ck` records sealed before the rotation, and which an active-only summary can never tell it about |
| 6 | The evidence-based retire and re-mint: no private for an advertised generation **and** no key package to ask → retire it and mint fresh, on the first observation | sole enrollment, advertised private absent, no key package → retires and mints. **Control arm required**: a sibling key package present → waits and does not retire. Without the control this passes for the absence of the effect |
| 7 | Docs and acceptance sweep | `catalogue_test.dart` going red **is** the check. Four acceptance scenarios name `_nskeylock` (`a3_self_data_test`, `a5_rotation_test`, `b5_edge_cases_test`, `cross_cutting_test`), plus `acceptance.md` rows, `test/acceptance/README.md`'s pinned counts, `design.md` section 1.3's shape table, and `wire_literal_pins_test.dart` |

**Routing notes — [14.20](#1420-building-rulings-98-and-99--the-sequence)'s
question applied before building, not after.**

- Row 3 reads like bookkeeping ("write a status field") and routes into the
  **summary composer**, exactly as B5's did: the healer must be told what was
  retired, or it recomputes from a log it re-reads and the retirement is
  invisible until the write lands.
- Row 4 reads like deleting a cache and routes into **every `put`** —
  `CkManager.ensureCurrent` runs per write and reaches `currentPublic`, so
  removing the in-memory short-circuit puts the 15-minute `advertisementTtl`
  cache on that path instead of nothing.
- Row 6 reads like a heal and routes into **`rotate`'s meaning**: it is the
  first caller that retires a generation it did not mint.

⚠️ **Two files to read before starting, neither of which the rows name.**
`nskey_rotation.dart` is unexamined and may carry a single-generation
assumption; and `tests/at_functional_test/test/pq_signing_root_mint_lock_test.dart`
drives `ring.rotate` live in its third test, so row 3 changes what that file
asserts.

---

### 14.24 The nskey mint elects a winner — decisions 105

⛔ **Demoted here 2026-08-16 when 14.24 completed**, replacing the pre-build
snapshot copy that used to sit at this position — which still called the item
open and its at_server PR unmerged. This is the finished section, moved whole
rather than summarised, and it is the only copy.


⚠️ **THIS is the model being built.**
[14.23](implementation-plan.md#1423-per-generation-nskey-records--decisions-104-rejected) is REJECTED.
[decisions 105](decisions.md#105-the-nskey-mint-elects-a-winner-2026-08-16)
rules the design; this is the order. One nskey record, and a lock used as an
**election token with a cooldown** rather than a mutex.

**The requirement, which had never been written down:** *if enrollments A, B
and C all decide they need to mint, only one of them eventually does.* Every
earlier argument about the lock was about mechanisms with no agreed property to
hold them to, which is why "is 14.19 item 18 worth fixing" stayed unanswerable
for two sessions.

✅ **DONE 2026-08-16.** All seven rows are built and proven against a live
atServer: `tests/at_functional_test` runs **166/166, `EXIT=0`** on the rebuilt
`at_virtual_env:local`.

The live run found what the protocol implies
and nobody had written down: **the cooldown binds rotation too.** A rotation of
a namespace minted or rotated within `mintLockTtl` is refused, because nothing
releases the lock but its ttl. Four functional tests failed on it.

⚠️ **No unit test can find this.** The interlock *is* the atServer refusing a
second create of an immutable record, and a mocked `executeVerb` accepts the
second take happily — so every unit test of this path is green whether or not
the cooldown exists. gkc ruled 2026-08-16 to **accept** it
([decisions 105.6](decisions.md#1056-built-the-cooldown-binds-rotation-too)):
`mintLockTtl` became injectable (`PublishedNskeyKeyRing.lockTtl`,
`PqSigningRoot.lockTtl`) so a live test need not wait two minutes between its
mint and its rotation, and `revokeEnrollmentAndRotate`'s partial state — it
revokes first, so a refused rotation leaves the enrollment cut off but still
holding the live generation — is named in its own `severe` log rather than
retried.

**Rows 3 and 5 depend on an at_server change that ✅ MERGED 2026-08-16 18:46Z:
[at_server PR #2751](https://github.com/atsign-foundation/at_server/pull/2751)**,
branch `gkc-expired-immutable-blocks-create`, now `00c2f9a6` on `origin/trunk`.
It was open for most of the day this work was built; a reader who saw an earlier
version of this line has a stale gate.

⚠️ **Merged is not deployed, and this gate is about a RUNNING atServer.** A
ttl-only release is correct only against one carrying the fix. `at_virtual_env:local`
is rebuilt and does; `atsigncompany/virtualenv:vip` and every deployed atServer
need their own rebuild, which the merge does not perform. Re-derive both halves:

```bash
gh pr view 2751 --repo atsign-foundation/at_server --json state,mergedAt
git -C ~/dev/atsign/repos/at_server merge-base --is-ancestor 425a2f29 origin/trunk
```

⚠️ **Cite the PR, not a SHA.** This block named `b5654bfd`; gkc rewrote the
commits before pushing, so that SHA no longer exists anywhere. The branch now
carries the fix plus an at_secondary_server version bump. Re-derive rather than
trust this line:

```
gh pr view 2751 --repo atsign-foundation/at_server --json state,mergedAt
git -C ~/dev/atsign/repos/at_server log --oneline origin/trunk..origin/gkc-expired-immutable-blocks-create
```

⚠️ **A merge is not enough for rows 3 and 5** — they need an atServer that
*runs* the fix. The local `at_virtual_env:local` has been rebuilt and does; any
other deployment needs its own rebuild, and a client relying on ttl-only
release is incorrect against an atServer without it.

| # | What | The differential |
|---|---|---|
| 1 | ~~A **remote-only** read of the published advertisement for the mint path. ⚠️ **NOT by changing `currentPublic`** — that is also the sender path, reached from `CkManager.ensureCurrent` on *every* put, so making it remote puts a round trip on the write path and breaks offline writes. A separate read, always remote, skipping both caches — the shape `PqSigningRoot.publishedRoots` already has | a sibling enrollment publishes; this client's pre-check sees it without waiting for sync. ⚠️ **Scope: `published_nskey_key_ring.dart:450` is the read to change, but it is NOT the only optionless read in the subsystem** — `ck_manager.dart:248` and `symmetric_aes_gcm_provider.dart:250` are optionless too. Those two are **content-key conveyance** reads rather than advertisement reads and are plausibly correct as local-first, so they are out of scope *by argument, not by absence*. Re-derive before believing either way: `git grep -n -A3 "atClient\.get(" -- packages/at_client/lib/src/crypto/nskey/`~~ ✅ **BUILT.** `PublishedNskeyKeyRing.publishedAdvertisement` is the new read. Three mint-path call sites use it — `mintAndPublish`'s post-loss read, `rotate`'s precondition, and `NskeySeeding.seed`'s pre-check. ⚠️ **This said `currentPublic` is untouched until 2026-08-25.** It still reads local first — the reason above is unchanged, and a round trip by default would still break offline writes — but it now falls back to the atServer when local storage holds nothing, which is what makes it correct for the minter to publish the advertisement to the atServer alone |
| 2 | ~~The **winner's re-check under the lock**, which the nskey path has never had. `_mintUnderLock` (root) re-reads; `_mint` (nskey) does not~~ ✅ **BUILT** as `_mintUnlessPublished`, which wraps `_mint` on the `mintAndPublish` path only — `rotate` still runs `_mint` directly, because a rotation that adopted what it found would have rotated nothing while reporting success | a winner that published between the pre-check and this client taking the lock is adopted, not overwritten |
| 3 | ~~`withLock` **stops releasing** — the ttl is the release~~ ✅ **BUILT.** `MintLock._release` is deleted, and `withLock` now **refuses a lock key with no ttl** — with nothing deleting the record, a missing ttl means it is never released at all rather than released late | a holder that finishes does not free the lock; a second enrollment is refused until the ttl elapses. This is what made [14.19](#1419-small-items-raised-2026-08-12-and-not-yet-acted-on) item 18 disappear rather than be fixed |
| 4 | ~~The **loser**: re-read once, adopt a published generation, otherwise **fail** with a reason~~ ✅ **BUILT.** Both arms now have a test; the `StateError` says why the loser must not mint and that the retry is the next client start | lock held + a generation published → adopts. Lock held + nothing published → fails naming the contention, and a waiting `put` fails loudly rather than hanging on another device's crash |
| 5 | ~~The **lease self-abort**~~ ✅ **BUILT** as `MintLease`, which `withLock` hands to the mint. ⚠️ Its deadline is stamped **before** the take goes out, never after: the atServer starts the ttl at or after the send, so stamping from the reply would have the client believe it still held a lock the atServer had released. Checked immediately before each publish, so a keygen or a suspend cannot happen after the check | a mint that overruns the ttl publishes nothing. Without it the requirement fails with everything else correct, because the bounded window bounds when the three *attempt*, not how long the winner *takes* |
| 6 | ~~The "crash backstop" claim is **false as written**~~ ✅ **BUILT** — both sites in `nskey_records.dart` now say the ttl is what releases the lock, and `mintLockTtl` says it is also the winner's own budget | none — a doc correction |
| 7 | ~~Docs and acceptance sweep~~ ✅ **BUILT.** `acceptance.md` steps A3.2 and B6 said the holder "releases"; `design.md` §1.3 and the B5b sequence said the same. All now say the ttl releases it, and §1.3 states the winner's re-read | `catalogue_test.dart` and `docs_structure_test.dart` staying green is the check |

**Two things found while checking the protocol against the tree, which the rows
above assume.**

- **Exactly two production callers mint**: `nskey_seeding.dart:100`
  (`mintAndPublish`) and `nskey_rotation.dart:152` (`rotate`). Re-derive:
  `git grep -n "mintAndPublish\|\.rotate(" -- packages/at_client/lib packages/at_onboarding_cli/lib`
- ~~**`rotate`'s precondition read is asked twice.**
  `NskeyRotation.rotateNamespaceKey:145` calls `ring.currentPublic` to refuse a
  cold-start rotation, and `ring.rotate:320` calls it again. Both are
  local-first, so row 1 has to reach both — and they are the same question
  asked twice, which is worth collapsing rather than converting twice.~~
  ✅ **COLLAPSED** into `ring.rotate`, which now returns
  `({rotated, superseded})` so its caller names what it superseded from the read
  already made. The cold-start refusal and its message live in one place.
- **A third advertisement read is still local-first, and is out of scope by
  argument.** `NskeySeeding.requestMissingPrivates` (`nskey_seeding.dart:186`)
  reads `currentPublic` to decide which generation's private to ask for. It is
  the *pull* path, not the mint path, so nothing it does can overwrite a key —
  but a stale read there asks for a superseded generation, and the heal then
  waits for the next start. Worth deciding on rather than leaving undecided.

---


## 15. D1 burn-down — the single index of what D1 owes

**Why this exists.** There was no one place to answer "what is left for D1".
The work is spread across [14.18](#1418-the-remaining-d1-initial-development-sequence)'s
sequence, its stage-5 table, [14.19](#1419-small-items-raised-2026-08-12-and-not-yet-acted-on)'s
small items, [14.22](#1422-making-the-signing-root-rotatable--decisions-101), and
GitHub — and 14.19 item 14 admits the gap in its own text, having been parked
there "because this project has no other checked-in owed-work list". A
context-free reader asked to find the owed work on 2026-08-15 found four
locations and said it could not have assembled them unaided.

⚠️ **This is an INDEX, not a second source of truth.** Every row points at the
entry that owns the detail, and carries the command that re-derives its state.
**If a row here and its owning entry disagree, the entry wins and this row is
stale** — that is the failure mode every "current state" table in this project
has had, so it is stated rather than hoped for. Re-derive before acting; do not
cite this table as evidence.

**D1 ends when every acceptance test passes and every rail is green, the
posture matrix included** — ruled by gkc 2026-08-23. What D1 requires is that
the acceptance set is **complete, implemented and verified**. Everything else
is a judgement call.

⚠️ **This definition moved twice on 2026-08-23 and both earlier forms are
wrong.** It read "ends at step 34 — the spike carved into stacked PRs and
merged. Publishing and R-2 follow it and are not D1", and then briefly "ends
when at_auth 4.0.0 is published, the staged status value is added and step 20's
rotation arm is green". The carve, the publishes and the rotation arm are all
still owed and still sequenced — they are simply not what *defines* the
boundary. R-2 still follows D1.

⛔ **"All acceptance tests pass" is true today and does not yet mean what this
definition needs.** All 69 catalogue rows read `PROVEN` (68 live, UC-C1.3
withdrawn) and all 68 live ones have a scenario — but the rail checks
**structure only**: that a scenario exists, that ids resolve, that counts
match. Nothing checks that a scenario proves what its row *claims*, and
`proves:` prose is matched against nothing. The one known overclaim, three
clauses of UC-A2.5/UC-A2.6, was found by hand. The clause-by-clause audit is a
D1 gate and is in the live plan's [`## TODO`](../implementation-plan.md#todo).

### 15.1 Open work — re-derive before acting

| # | What is owed | Owner | State |
|---|---|---|---|
| 1 | ✅ **14.22 is COMPLETE — all seven rows landed 2026-08-15** | [14.22](#1422-making-the-signing-root-rotatable--decisions-101) | Row 6 made the record mutable behind `_rootlock@<atSign>` and generalised `NskeyMintLock` into `MintLock`; row 7 proved the boundary and needed no new mechanism, only the composite scenario. **`decisions.md` 101 is fully built.** Nothing in this row is owed. ⚠️ **Step 27 (row 5) has since landed too**, 2026-08-15, and it was the right one to take first for the reason recorded there: it changed the signed bytes, so everything signed after it is signed under the shape that stays |
| 2 | **Step 20's rotation arm** — enrollment then an `enroll:update` APKAM rotation mid-run | [14.18](#1418-the-remaining-d1-initial-development-sequence) step 20 | **Stays in D1** (gkc, 2026-08-23) — which is why D1's boundary moved past the carve. Chain: publish at_auth 4.0.0 → add the `pending` value → build the arm. Needs its own CRAM atSign. ⛔ **The "wait for the fleet" gate is CLOSED**: it assumed a released reader could meet a `pending` status, and the two formats are disjoint for every file that exists — 3.3.0 dispatches on `version`, and a document without one never reaches its `keys` parse, while a 4.0.0 document with typed material emits `version: 1` and no `keys`. The only reachable conflict needs a 4.0.0 typed write into a keyfile a 3.3.0 app also opens, and **no production `.atKeys` or keychain entry holds any PQ key material** (gkc, 2026-08-23) |
| 3 | **Step 24** — a client with no enrollment id is treated as fully privileged | [14.14](#1414-a-client-with-no-enrollment-id-is-treated-as-fully-privileged) | ✅ **CLOSED 2026-08-23** — both halves were already ruled elsewhere and nobody had closed the row. Privilege: the resolver's own dartdoc, *"a client with no enrollment id is authenticating with the atSign's own keys, which is full privilege by construction rather than by grant"*. Identity: [14.18](#1418-the-remaining-d1-initial-development-sequence) step 13 ruled that a client with no enrollment publishes its `_apsk` under `primary` deliberately. Moved to PARKED so the question is not re-derived |
| 4 | **Step 25** — a `mintLegacyMaterial:false` atSign cannot write a public record | [14.12](#1412-a-mintlegacymaterialfalse-atsign-cannot-write-a-public-record) | ⛔ **NOT D1 (gkc, 2026-08-23)** — it gates the **post-R-2 stop-release**, not this one. Both moves it needs (public-record signing onto the ML-DSA root, self data off `selfEncryptionKey`) are B-3 phase 1, which is parked, and nothing about it blocks the carve. The live assertion in `pq_legacy_interop_live_test.dart` keeps it pinned, and the flag must still not be recommended to anyone |
| 5 | ✅ **Step 27 — DONE 2026-08-15.** Domain separation on the signed envelope | [14.8](#148-domain-separation-on-the-signed-envelope) | Landed: per-use `EnvelopeType` in the protected header, `expecting` at both verify entry points, `at-root-link:` on the root link's signed bytes, and the re-anchor that change forced. [`decisions.md` 103](decisions.md#103-an-envelope-says-what-it-is-for-and-a-verifier-says-what-it-wants-2026-08-15) |
| 6 | **Step 28** — NoPorts carries its own copy of the envelope shape | [14.7](#147-noports-carries-its-own-copy-of-the-envelope-shape) | ⛔ **NOT D1 (gkc, 2026-08-23)** — moved to PARKED with its trigger stated: the obligation to name NoPorts fires when **RFC 7515 becomes a consumer-facing claim**, which it is not. Measured 2026-08-22: the string appears in `design.md` and `detail/decisions.md` and in **no file under `packages/`**. 14.7's own text says a migration here does not break NoPorts |
| 7 | **Step 29** — three audit residuals (was four; UC-A3.4's live self-direction is done) | [14.16](#1416-four-residuals-the-issue-tree-audit-surfaced-2026-08-09) | ⛔ **STEP 29 LEAVES D1 — all four dispositioned 2026-08-23.** ⚠️ This cell listed four as open while saying three, and included UC-A3.4 which it had just called done. ① perf ceiling → post-D1 cleanup (#2153). ② UC-A3.4 → done 2026-08-17. ③ SS-4 resume → **ruled NO RESUME**: the election makes republishing a filed-but-unpublished pair a regression, since it can overwrite a newer winner's advertisement with a key only the loser holds; re-filed as **orphan growth**, because `store()` calls `addKey` and nothing in `crypto/nskey/` retires a filed private. ④ IS-1 drift → not D1: a separate track whose implementation is at_server #2683, open and untouched since 2026-08-06, and already ruled to be pared back |
| 8 | **Step 30** — `deprecated_member_use` across the workspace | [14.11](#1411-deprecated_member_use-findings-across-the-workspace) | **STAYS IN D1, with the bucket-B migration** (gkc, 2026-08-23). Re-measured 2026-08-23: **754** findings (at_client 396, at_onboarding_cli 205, at_auth 153, at_lookup **0**) — the table in [14.11](implementation-plan.md#1411-deprecated_member_use-findings-across-the-workspace) said 345/183/110/28. Five buckets; only **B** has a replacement that exists: 71 credential-ladder uses (`enrollmentId` 59, `signingAlgoType` 12) that move onto the `AtAuthenticator` seam at_lookup 3.7.0 ships — 24 sites in `lib/`, 47 in tests. A (AtChops API, 530) and C (legacy flat fields, 118) are transient and get no ignores yet; D (27) is at v5 |
| 9 | **Step 31** — pre-PR rails checklist | [14.15](#1415-pre-pr-rails-checklist) | ✅ **NOTHING OWED since 2026-08-10** — this cell said "Open" while 14.15's own body opened "✅ NOTHING OWED". Its single item is struck; what remained was the external image gate, which is settled (see row 13) |
| 10 | ✅ **D1's tail — DONE 2026-08-15.** `signingAlgo`'s dartdoc in at_commons | [14.20](#1420-building-rulings-98-and-99--the-sequence) row D1 | Landed on **three** declarations, not the one the row named: `EnrollParams`, `EnrollVerbBuilder` and `PkamVerbBuilder`. at_commons **517/517**, re-run at this state rather than carried forward from `224460d8b` |
| 11 | **14.19's open small items — 17 unstruck of 36, of which item 15 is resolved and kept only for its findings, and items 20–22 are examined-and-deliberately-left rather than work.** ⚠️ *This cell said **18** until 2026-08-18 against an actual 10, then **10** until 2026-08-19 against an actual 18 — the same number, wrong in both directions a day apart; re-derive it with the command below rather than reading any of them.* ✅ **Item 15 (the `_apsk` third writer) is EXAMINED, RULED and CLOSED** (2026-08-15) — do not pick it up. Re-derive the count rather than trusting it: `awk '/^### 14.19 /,/^#### 14.19.1/' docs/projects/pq/detail/implementation-plan.md \| grep -cE "^[0-9]+\. \*\*"` — ⚠️ **this named the LIVE file until 2026-08-18**, where the list does not live, so it printed `0` and exited 1, which reads as "no open work". That exact bug was found and fixed in the plan's own state block on 2026-08-16; this second copy survived the fix, which is why a re-derivation command gets grepped for rather than corrected where you found it | [14.19](#1419-small-items-raised-2026-08-12-and-not-yet-acted-on) | Open. **Item 8 is the only one waiting on a ruling** (typed key material is not self-encrypted at rest while the flat fields are). Item 10 is an unexplained functional run with two disproven theories. Item 14 is not PQ at all |
| 12 | **The nskey mint elects a winner** — one record, the lock becomes an election token with a cooldown, and only one of several enrollments that all decide to mint eventually does | [14.24](#1424-the-nskey-mint-elects-a-winner--decisions-105) | ✅ **DONE 2026-08-16**, all seven rows, **in D1**. The at_server fix rows 3 and 5 needed merged as [PR #2751](https://github.com/atsign-foundation/at_server/pull/2751) (`00c2f9a6` on trunk) — ⚠️ merged is not deployed: `at_virtual_env:local` runs it, `virtualenv:vip` does not. ⛔ **[14.23](#1423-per-generation-nskey-records--decisions-104-rejected) is REJECTED** — do not build it. Re-derive: `git grep -n "nskeyMintLockKey\|withLock" -- packages/at_client/lib` |
| 13 | **Steps 32–34** — carve into stacked PRs, merge to trunk | [14.18](#1418-the-remaining-d1-initial-development-sequence) | ✅ **THE IMAGE GATE IS SETTLED** — it was closed by moving CI to `dev_env`, and this cell claimed it was still blocking until 2026-08-23. Re-derive: `grep -n VIRTUALENV_IMAGE .github/workflows/at_client_sdk.yaml` shows `atsigncompany/virtualenv:dev_env` at both the functional and e2e jobs. **Six of eight train positions are through** — at_commons, at_chops, at_lookup, at_server_status and at_auth are all merged (at_auth on 2026-08-25). ⚠️ This read "Five … at_auth is PR #2179, open and CI-green". Left to carve: at_client, at_client_flutter, at_onboarding_cli. The spike branch itself never merges |

**Not owed, and worth stating so nobody re-opens them:** step 11 was labelled
`PARTLY DONE` while its own cell closed with `✅ DONE 2026-08-13, with step 12`.
⚠️ **The label is now corrected** (2026-08-18) — it stood for five days *after*
this paragraph diagnosed it, which is the lesson: writing "the label is stale"
beside a stale label leaves every count still reading the label. Step 23 folded into the rollout axis.
Step 26 closed when the atServer cache race was fixed (`16dd457f`, merged).
Acceptance's two skipped scenarios are blocked on the **KE-2 project**, not
owed a test.

### 15.2 Re-derive every row above

Run these rather than trusting the table. Each answers one row.

```bash
# row 1: which 14.22 rows have landed? Row 1 landed when this file started
# composing apskAdvertisement; row 2 is unbuilt for as long as the prefix
# still names one algorithm.
git grep -n "keyIdPrefix =\|apskAdvertisement" -- packages/at_client/lib/src/crypto/nskey/

# row 11: which 14.19 items are still open? (~~struck~~ ones are done)
awk '/^### 14.19 /,/^#### 14.19.1/' docs/projects/pq/detail/implementation-plan.md \
  | grep -E "^[0-9]+\. \*\*"

# rows 3-9: the stage-5 table, which owns steps 23-31
awk '/^\*\*Stage 5/,/^\*\*Stage 6/' docs/projects/pq/implementation-plan.md

# acceptance: what is skipped, and on which blocker.
# Anchor on "}, skip:" — a bare "skip:" also matches catalogue_test.dart's and
# manifest.dart's prose ABOUT skips and reports 5 where the answer is 2.
grep -rn "}, skip:" packages/at_client/test/acceptance/*_test.dart
grep -n "blocked:\|owed:" packages/at_client/test/acceptance/blockers.dart

# row 2 and row 12: the external gates. The at_auth release is a pub.dev
# question; the atServer image gate is gkc's call and is NOT to be checked
# against atsigncompany/virtualenv:vip (ruled 2026-08-13).

# rails, all four packages
cd packages/at_auth           && dart test --concurrency=1   # 312
cd packages/at_client         && dart test --concurrency=1   # 1327 (2 skipped)
cd packages/at_client         && dart test test/acceptance --concurrency=1  # 58 (2)
cd packages/at_onboarding_cli && dart test --concurrency=1   # 39
cd tests/at_functional_test   && ./runLocal.sh               # 165/165
# measured at 7c6b3e7f2 (2026-08-15). Every figure in this project has been
# wrong at least once by being carried forward — the COMMAND is the value
# here, not the number beside it.
```

### 15.3 After D1

The release programme is **not** part of D1 initial development, and it ends
with **R-2**, the 4.0.0 posture flip: the default `PqPosture` becomes
`pqActive` ([ruling 113](decisions.md#113-pqposture-three-postures-and-the-rollout-they-drive-2026-08-18)).
Still a pure default-flip carrying no code of its own, so anything the posture
needs lands in D1 before it.

The ordered publish list is
[above, in section 10(a)](#what-still-has-to-be-published-in-order), and is not
restated here.

---

### 14.27 The ledger's remaining append-only rot

Raised 2026-08-16 when gkc ruled that a heading states a ruling's *current*
outcome and that falsified claims are replaced, not layered over. Rulings 104
and 105 were corrected, the doctrine sentences at
[84](decisions.md#84-phase-7-the-functional-packs-live-tests-stop-claiming-to-be-the-e2e-pack-2026-08-11)
and [89](decisions.md#89-phase-7-the-section-symbol-keeps-the-two-jobs-it-is-good-at-2026-08-11)
were marked overruled, and [46] moved to `PARTLY SUPERSEDED by [48]`.

✅ **The status audit is DONE.** A scan flagged 41 rulings whose body records a
falsified claim while the index said `LIVE`. Printing the *sentence* carrying
each trigger — rather than the one-line summary, which cannot tell "this ruling
was falsified" from "this ruling says another one was" — separated them:

- **Most were healthy.** "superseded" naming a *generation* of key material
  (47, 76), "was wrong" about the catalogue (29) or about a checker (85), a
  timeline that records other rulings' supersessions (7).
- **11 were real, and are fixed**: 13, 18, 42, 45, 56, 68, 69, 70, 91, 93, 98
  each carry a dated `Amended <date>` marker in the body while the index said
  `LIVE`. The ledger's own vocabulary reserves `AMENDED` for exactly that, so
  each row now carries it with the latest date. Four (13, 91, 93, 98) were
  read directly; the other seven matched the same unambiguous marker.

✅ **Both citation debts are DISCHARGED**, and each was smaller or different
than the ruling that deferred it said:

- [84](decisions.md#84-phase-7-the-functional-packs-live-tests-stop-claiming-to-be-the-e2e-pack-2026-08-11)
  said "two earlier rulings cite the old filenames". It was **3 citations
  across 2 files** — `enrollment_pq_key_exchange_e2e_test.dart` and
  `nskey_data_path_e2e_test.dart`, both now `*_live_test.dart`. ⚠️ A first
  pass also reported `retrofit_e2e_test.dart` and
  `retrofit_retirement_e2e_test.dart` as dead; they are **alive**, in
  `tests/at_end2end_test/test/pq/` — the check had looked in the functional
  pack only.
- [89](decisions.md#89-phase-7-the-section-symbol-keeps-the-two-jobs-it-is-good-at-2026-08-11)
  said 74 section symbols were owed conversion. **54 converted plus 19 link
  labels**; the remaining **17 stay by 89's own classification** — external
  standards (`SP 800-227 §4.3`, `RFC 9180 §5.1`, `RFC 7515 §7.2.2`,
  `RFC 8725 §3.11`) and 89's own quoted examples of the notation.
  ⚠️ **The scripted conversion mis-resolved five references and broke one
  heading**, all caught by verifying every link afterwards rather than by the
  script: `design §4` without the `.md` resolved to *ruling* 4; two labels
  that already contained `§` became nested links; and ruling 76's heading
  carried a `§50`, so converting it changed the slug and orphaned the index
  row. 76's heading is now short and its two pointers moved with it.

Re-derive rather than trusting the numbers above:

```bash
# a dated self-amendment in the body is now asserted against the index status
dart test packages/at_client/test/acceptance --concurrency=1
```

---

### 14.26 A comment in at_server is now false

⚠️ **This lands in at_server, not in this repo.** It is recorded here because
this is the list the work is driven from, and a correction owed in a sibling
repo dies if it is only written in the ruling that found it.

`packages/at_persistence_secondary_server/lib/src/spec/keystore/at_metadata_builder.dart:46`
carries, above the immutable-stickiness branch:

> *"Note: this condition never occurs right now but we will leave it here for
> safety's sake"*

It never occurred **because the update handler refused every such update**. The
fix on [at_server PR #2751](https://github.com/atsign-foundation/at_server/pull/2751)
makes an update delete an expired record and proceed, so the branch is now
reachable and the comment is false — see
[decisions 104.10](decisions.md#10410-fixed-in-at_server-and-merged).

⛔ **It missed its ride.** This row said "cheapest while the PR is still open:
it rides that branch". PR #2751 **merged 2026-08-16 18:46Z** without it, and
the comment is still there — verified against the merged trunk, at the path
above, line 46. So this is now a standalone at_server change off `trunk`, not
a rider, and it is the only thing 14.26 still owes.

Re-derive rather than trusting this row:

```bash
git -C ~/dev/atsign/repos/at_server grep -n "never occurs right now"
gh pr view 2751 --repo atsign-foundation/at_server --json state,mergedAt
```

---

### 14.28 Live PQ proofs that no use case names

Raised and settled 2026-08-16 by auditing the test tree the way the mint
election's gap was found: **a live test file that no `provenIn` cites**. Live
tests are expensive and deliberate, so one nobody cites is a behaviour somebody
thought worth proving and the done-bar never named.

**36 of 60 live files are uncited, and most are correctly so** — at_client's
pre-PQ suites (sync, notify, put, delete) were never what this catalogue is
about. Nine were PQ. gkc ruled each:

**Five became use cases** ([12.8](../acceptance.md#128-uc-b58--a-client-that-configures-nothing-still-takes-part)–[12.12](../acceptance.md#1212-uc-b512--the-owner-verifies-her-own-advertisement-as-a-peer-would)),
every one citing a proof that already existed:

| use case | the behaviour that had no done-bar row |
|----------|-----------------------------------------|
| UC-B5.8  | a client with **no `CryptoConfig` at all** resolves providers and opens what a peer sealed. The strongest product claim D1 makes |
| UC-B5.9  | a conveyed private addressed to **another** key package is not filed — arrival is not entitlement |
| UC-B5.10 | an enrollment **not entitled** to the root does not ask. The refusal half of UC-B5.1 |
| UC-B5.11 | an enrollment that missed the mint **heals from a holder** rather than minting a rival generation |
| UC-B5.12 | the owner verifies her own advertisement by the **same path a peer takes** |

**Four did not**, and the reason is the point of the row:

- `enrollment_key_package_live_test.dart` — the key package surviving
  `enroll:request` is [UC-A2.4](../acceptance.md#34-uc-a24--the-key-package-advertises-the-kem-the-deployment-configured)
  in substance; it cites a different proof, which is a citation question, not a
  coverage one.
- `pq_rollout_matrix_test.dart` — the sender/receiver stage matrix is
  UC-B3.1–B4.4 swept systematically, and the file already cites `UC-G1.14`.
- `nskey_published_ring_test.dart`'s *rotation keeps the old private* is
  [UC-A5.1](../acceptance.md#61-uc-a51--rotate-a-namespace-key-post-compromise).
  Its other two tests became UC-B5.12.
- `auth_session_handoff_test.dart` — `fromAuthSession` rebuilding a connection
  is SDK session plumbing, not PQ. ⚠️ **An earlier version of this row said it
  had no `test(` at all.** It has one; the name is on the line after `test(`
  and the grep required them on the same line.

**The B5 cluster is now "edge cases", not "retrofit edge cases"** — neither the
mint election nor these are retrofit, and the label was already false when
UC-B5.4 landed.

---

### 14.25 Three projects state partial completion, and six state none

Raised and settled 2026-08-16. The row recorded a discrepancy without a
diagnosis; each of the nine has now been read against the tree. **The burn-down
was right about four, the headings were stale for two, and two entries under
DONE genuinely owe work.**

**The three that stated incompleteness:**

| entry | said | is |
|-------|------|-----|
| **SS-1c** | live drive still owed | ✅ **discharged.** `enroll:listns:<ns>` is issued at `enrollment_directory.dart:143`, from **4 production call sites** in `pairwise_secret_sharing.dart`, driven by 2 live functional tests |
| **SS-4** | ABOUT HALF LANDED | ✅ **stale.** Three of its four owed items are struck; the fourth, key-transparency publication, is scoped out by [ruling 24.4](decisions.md#244-built-since-and-what-is-still-owed) |
| **S-3** | PARTLY LANDED | ⚠️ **stands.** Three small items: a migration test on a v(N-1) fixture, a keychain round-trip on a real device (**blocked** — no `integration_test` harness in this repo), and `LocalKeystoreAtKeysIo`, still "not needed at this time". The self-encryption re-wrap is a recorded decision, not a debt |

**The six that stated nothing:** P-3, RF-1 and RF-SRV carry no owed language,
and RF-2c says outright *"still owed against this project: nothing"* — the
burn-down was right about all four. Two were not:

- **SS-2** owes the atServer's `__ssenv` behaviour, so DEP4's update-put
  auto-notify is unbuilt. ⛔ **Its second owed item was already fixed and the
  entry never said so** — it claimed `_getSigningAlgoType` branches on ecc and
  rsa2048 only, so a PQ-APKAM "would be verified as RSA and fail". That method
  no longer exists; `ApkamSignatureVerifier` handles `mldsa65` against the key
  **recorded on the enrollment**. ML-DSA PKAM has been passing live for days
  against `at_virtual_env:local` while this paragraph said it could not work,
  and nobody reconciled the two.
- ~~**B-1** owes everything beyond envelope delivery (`pushSecretToNames…`), a
  unit fixture that backs local storage and the atServer with **one map** …, and
  UC-A3.4's self direction — owed rather than blocked since `ConcurrentClients`
  landed~~ ([#2093](https://github.com/atsign-foundation/at_client_sdk/issues/2093))
  — ✅ **all three closed**, the fixture on 2026-08-16 and the other two by
  2026-08-18. ⚠️ **This bullet is the finding below happening to itself**: it
  claimed work was owed that had since been done, in the very section whose
  conclusion is that every wrong entry was wrong in that direction. Re-read
  2026-08-18; see [14.29](../implementation-plan.md#1429-the-residuals-1425-surfaced).

**The general finding, which is why this is worth a body.** Every wrong entry
was wrong in the *safe-looking* direction: three claimed work was owed that had
since been done. A stale "owed" reads as conservative and costs a rebuild;
`_getSigningAlgoType` is the sharp case, because the tree contradicted it
loudly — a passing live suite — and the contradiction sat unexamined because
nothing reads a project entry when a test goes green.

### 14.33 CLOSED: the `shared_key.*` refusal was never reachable

Raised by [14.31](#1431-a-refused-watermark-write-permanently-disables-the-monitor)
as the remaining half of what 70.1 observed, and recorded in the TODO table as
"the genuine remaining R-2 blocker". It was neither.

**`shared_key.*` cannot reach the refusal.** The two records are written by
`AbstractAtKeyEncryption` straight at a `Secondary` with a raw verb
(`legacy_encryption.dart:293` and `:177`), not through `PutRequestTransformer`:

```dart
var updateSharedKeyForCurrentAtSignBuilder = UpdateVerbBuilder()
  ..atKey = (AtKey()
    ..key = '${AtConstants.atEncryptionSharedKey}.${atKey.sharedWith?.replaceAll('@','')}'
    ..sharedBy = atKey.sharedBy)
  ..value = encryptedSharedKey;
await secondary.executeVerb(updateSharedKeyForCurrentAtSignBuilder, sync: false);
```

No transformer, no crypto runtime, no refusal. And the writer is *downstream* of
the refusal in any case: `AbstractAtKeyEncryption.encrypt` runs only from
`LegacyEncryption.build`, whose sole caller is the legacy provider's `encrypt`
(`legacy_crypto_provider.dart:19`), and `encryptForPut` calls
`refuseLegacyIfDisallowed` **before** `provider.encrypt`. Under the flag the
legacy path is refused one step earlier, on the data key, so the `shared_key.*`
write is never attempted. Reads are untouched — `decrypt` goes through
`LegacyDecryption`, which the refusal does not guard.

**The test that pinned it never entered production's path.** `providerIdFor` has
exactly two call sites (`crypto_runtime.dart:44` and
`put_request_transformer.dart:73`), and neither is ever handed a `shared_key.*`
key; the pin in `disallow_legacy_encryption_test.dart` hand-built one. It has
been re-pointed at a key the SDK genuinely produces — see
[14.35](#1435-notificationservicesend-throws-away-the-namespace-it-was-given).

**What is genuinely refused** is `NotificationService.send()` with a
single-segment namespace, which is [14.35](#1435-notificationservicesend-throws-away-the-namespace-it-was-given)
— a key-construction bug in one method, not a gap in the scheme.

**Consequence for R-2:** no client-side blocker remains. The gates that do stand
are external and unchanged — the ecosystem-floor gate
([decisions 42](decisions.md#42-the-to-define-list-ruled-2026-08-05)'s five
downstream packages, recorded under the R-2 ecosystem-floor bullet) and
[decisions 37](decisions.md#37-legacy-key-material-is-retained-until-the-ecosystem-is-pq-not-the-atsign-2026-08-05),
which retains legacy material until the ecosystem is PQ rather than until one
atSign is.

⛔ **Do not re-open this on the grounds that `shared_key.*` is namespace-less.**
It is; that is not the question. The question is whether anything routes it
through the refusal, and nothing does.


## 16. Demoted from the live plan, 2026-08-22

These sections closed and were moved here whole. Nothing was summarised away:
demotion follows completion, never length, and the reasoning behind a closed
item is the part a later reader needs. Their anchors are unchanged, so a link
that used to reach them in the live plan now reaches them here.

⚠️ **This said each demotion left "a one-line row in the live plan's `## DONE`
table" until 2026-08-30.** There is no `## DONE` table any more — a closed item
leaves nothing behind in the live plan, which is what makes moving the body
here rather than deleting it the whole of the record.

### "withdraw" in two senses — swept 2026-08-30, the rename rejected

Moved here whole the day it closed. It was a P0, agreed with gkc that morning,
and what it asked for turned out to be wrong in a way worth recording — the
next reader will have the same instinct.

**What was done.** Sixteen comment edits across seven library files in at_auth
and at_client, qualifying every use of the word that left its sense to
context. Two phrases now carry the whole distinction: **"withdrawn from
service"** is a key taken out of use that stays advertised, and **"withdrawn
from the advertisement"** is a key that stops being named at all. Nothing else
moved — over the sweep no changed line is anything but a comment, and at_auth
(363) and at_client (1695) ran identical either side of it.

**⛔ The rename the row asked for was REJECTED (gkc, 2026-08-30), and that is
the part worth reading.** The row wanted `withdrawnSigningKeys`,
`withdrawnSigningKeysFor` and `apskEntries`' `withdrawn:` parameter renamed to
say `retired`, on the grounds that `retired` is what they mean. They do not
mean that.

- **`retired` is one token of an open vocabulary, and these members select a
  SET.** `KeyEntryStatus` and `CryptographicMaterialStatus` are both open
  `String`s, deliberately, each carrying a dartdoc on why a token this build
  has never seen must be passed through verbatim — *a retired key still
  verifies what it signed; a revoked one must not*.
  `withdrawnSigningKeysFor` selects on **not active and not `dead`**, which no
  single token names.
- **The rename would undo a fix rather than apply one.** `apskEntries`'
  parameter *was* called `retired`, and was renamed to `withdrawn` on
  **2026-08-22** under a **BREAKING** entry in at_client's CHANGELOG that
  gives the reason: the composer writes each entry's token through "instead of
  stamping every one of them `retired`".
- **`retained` is no better**, which is the obvious second candidate: every
  entry in the advertisement is retained, the active ones included, so it
  names a superset of what these members return.

**The row's second claim was false too.** It said *"No site now uses the
removed sense."* Five production sites did — in `at_keys.dart`,
`apkam_signing.dart`, `key_package_minting.dart`, `signing_key_minting.dart`
and `apsk_advertisement.dart` — and in three of them the removed sense carries
a real warning: the record is rewritten whole, so an omitted entry erases the
key. They could not have been renamed away, and qualifying them is what the
sweep did instead.

**The one site the row named specifically was already sound.** It cited
`apkam_signing.dart` for using the removed sense inside the dartdoc of
`withdrawnSigningKeys` — true, but that sentence qualifies itself, *"would
withdraw a key from the advertisement"*. What made it read oddly was the
**unqualified** uses around it, which is what the sweep fixed.

⚠️ **A rename here cannot reach the wire, and that was measured rather than
assumed** — so if the question is ever reopened, it is a question about
clarity only. The three identifiers appear in **zero** string literals in the
repo; the `_apsk` record's field names are `v`, `keys`, `kid`, `use`, `alg`,
`pub` and `status`, none of them `withdrawn`; and the latest published at_auth
(3.3.0) and at_client (3.14.0) contain **zero** occurrences, against controls
of 18 and 68 files naming `AtKeys`/`AtClient`.

**What the row said, verbatim:**

> ⛔ **Agreed with gkc 2026-08-30.** The word is used in two senses that contradict each other. **Retained**: `withdrawnSigningKeys`, `withdrawnSigningKeysFor`, `apskEntries`'s `withdrawn:` parameter, and ruling 126 at 12939 — an entry that STAYS advertised with status `retired`, so what it signed still verifies. ✅ **Removed — all four sites are gone as of the barrier deletion, 2026-08-30.** They were `signing_key_mint_barrier.dart` line 15, `apkam_signing.dart` line 176, `pq_client_bootstrap.dart` line 287 — and a **fourth this row missed**, `pq_client_bootstrap.dart` line 129 in the step-list dartdoc, which the "two of the three go with the deletion anyway" arithmetic left behind — *"publishing a minted key withdraws the authentication key from the advertisement"*, meaning it stops being named at all. ⚠️ `apkam_signing.dart` carries both senses **thirteen lines apart**: line 272 uses the removed sense inside the dartdoc of the getter whose name is the retained one. 
>
> **Why it matters beyond tidiness**: ruling 126 at 12935 rests the barrier deletion on *"It never **withdraws** a key anything could have signed with"*. In the retained sense that is trivially true; in the removed sense it is the actual, contestable claim. The word carries the argument and is ambiguous exactly there. 
>
> **What remains owed is the RETAINED sense only**: `withdrawnSigningKeys`, `withdrawnSigningKeysFor`, `apskEntries`'s `withdrawn:` parameter and their dartdocs still say "withdraw" where they mean **retired** — an entry that stays advertised. No site now uses the removed sense, so the ambiguity that carried ruling 126's argument is gone; what is left is a rename for clarity, not a correctness item.

### The PQ data-signing-key programme — eight commits, discharged 2026-08-30

Moved here whole on 2026-08-30, the day the last commit landed. It sat in
`## TODO` as a P0 while it was owed; with nothing left owed, the live list's
own convention is that the row goes. Nothing is summarised away — the
measurements below are the reason it is here rather than deleted, and several
of them are recorded nowhere else: commit 6's real blast radius, why the 28
functional failures were fixtures rather than the rule, why the CLI pack is
not a differential for commit 5, and that the e2e approvers needed no posture
change.

⛔ **Design settled with gkc 2026-08-30. Supersedes the former rows for the mint
barrier and for `sendEnrollRequest`'s stranded key package.** ✅ **The design is
now TRACKED**, in [`design.md` 9.8](../design.md#98-the-data-signing-key-an-enrollment-owns-from-birth):
it was moved there on 2026-08-31, corrected as it went, and the gitignored
`untracked/pq-data-signing-key-states.md` it came from was deleted — ⚠️ **it
had said in ten places what the programme then built differently**, and it was
a handoff no fresh clone could read. The sequence stays in
`untracked/pq-commit-sequencing-plan.md`, gitignored and spent: every commit it
planned has landed.

✅ **1, 2, 3, 5, 6, 7, 8 and 9 are DONE** — ⚠️ **this list omitted 7 until
2026-08-30**, when it landed, while two sentences away the same section said so;
a count with three homes went stale in one of them. `3308eddcb`, `56f2e5d39`,
`b8e4d5291`;
re-derive with `git log --oneline`. ⛔ **4 is DROPPED** ([ruling
127](decisions.md#127-a-client-with-no-enrollment-id-still-mints-and-publishes-its-own-signing-key-2026-08-30)).
✅ **Nine numbered, one dropped, EIGHT DONE — the programme is complete as of
2026-08-30.** What each turned out to be, and what proves it, is
[below](../implementation-plan.md#why-commit-7-needs-no-atserver-change). 1
at_auth files the advertised signing key's private half on the ordinary
enrollment path. 2 at_onboarding_cli mints and advertises one per algorithm in
`dataSigningKeyAlgorithms` — **the algorithm the enrollment will keep**,
rsa2048 at pqReady and mldsa65 at pqActive, not rsa2048 unconditionally — and
the same for `pq_native_onboard`. 3 `reconcileSigningKeys` stops miscounting a
legacy enrollment's rsa2048, **scoped to rsa2048** or it collapses the
auth/signing split at pqActive. ⛔ 4 **dropped**: a null-id client publishing
its own `_apsk.primary` is a mechanism `signing_key_minting_test.dart`
specifies, and 7 — which was to replace it — was recorded here as refused by
the atServer. ⚠️ **That reading was too wide**: only the auto-approve branch
refuses it, and 7 is reachable on today's atServer. 4 stays dropped on its
first reason alone — the null-id publish is a pinned capability, and a client
that never retrofits still needs it. See [ruling
127](decisions.md#127-a-client-with-no-enrollment-id-still-mints-and-publishes-its-own-signing-key-2026-08-30)
for the residual it leaves open. ✅ 5 **the mint barrier is deleted**. ⚠️ **2
and 3 did NOT fully carry it** — it still guarded one state, an enrolment
authenticating post-quantum that holds no signing key, and `serialiseApskWrite`
does not cover that because the lock serialises `_apsk` **writers** and this is
a **reader**. Deleted anyway (gkc): the state has no holder outside this tree,
and the deadlock is measured. [Ruling
126](decisions.md#126-the-mint-barrier-is-deleted-legacy-authentication-and-data-signing-are-one-keypair-2026-08-30)
is amended in place, because its own safety sentence was what was false. ✅ 6
`AtClientPreference` refuses an empty signing set with non-rsa2048 auth, and
any explicit authentication axis weaker than its posture. [Ruling
113](decisions.md#113-pqposture-three-postures-and-the-rollout-they-drive-2026-08-18)
amended. ⚠️ **The blast radius was TWELVE sites across four packages, not the
seven the design named** — the doc keyed its sweep on the literal
`authenticationKeyAlgorithm:`, while rule B keys on the RESOLVED value, so a
site naming only an empty `dataSigningKeyAlgorithms:` against a pq posture
trips it while appearing nowhere in that list. One such site was an assertion
rather than a fixture, so the rule **deleted a pinned property** (that an
explicit empty set beats the posture) rather than breaking a test. ⛔ **And the
doc's prescribed fix for the pinning fixtures — "rebase on pqReady" — would
have created fresh rule-D violations**; they take a non-empty signing set
instead, keeping the posture. The retired justification string was duplicated
in **two** packages, not one. 7 a pre-enrollment atSign retrofits at a PQ
posture. ✅ 8 a client with `!configuresPqProviders` neither approves a pq
request nor sweeps. **The discriminator is the ABSENCE of a wrapped symmetric
key**, not the advertised key package — a package rides every mode, and the
code already computed the right signal for its own reasons, so refusing after
it costs no extra round trip. A legacy request is still approved normally,
which is the whole of what such a client is for. The sweep is refused in
`EnrollmentServiceImpl` **and** gated in the startup: the gate is the startup's
answer, the throw is every other caller's. ⚠️ **`MockAtClient.getPreferences()`
is a CONCRETE override**, so `when(...)` cannot stub a posture — the mock and
its builder took a `posture` argument for this. ⚠️ **The refusal reddened 28
functional tests, and the FIXTURES were wrong, not the rule** — their approvers
named `PqPosture.legacy` to get two of its *other* axes (no retrofit, no
namespace seeding) and silently also got "no post-quantum providers", which was
never the intent and only became load-bearing when something asked. 15 approver
constructions now name `legacyPlusPqProviders`, which is legacy in every axis
except that one. The grid's legacy RECEIVER cell is deliberately left alone. ✅
9 a privileged approver without the root private signs a chain link when it
holds a data signing key, and conveys **nothing** when it holds neither — that
third arm is the one that must not guess, because `signingKeys` falls back to
the APKAM key and that key is dropped rather than retired. [Ruling
67](decisions.md#67-workstream-bi-the-sweep-anchors-to-the-root-2026-08-10)
amended: its "the every-start pull heals possession" does not hold, since the
pull and the sweep are both startup steps, so nothing re-attempts the link for
an enrolment approved while its approver was unpossessed.

⛔ **1 and 2 are a pair** — advertising without filing is worse than today. 1 is
separable only because it is a no-op alone. ✅ **7 IS DONE, and it needed no
atServer change — measured live 2026-08-30,
[below](../implementation-plan.md#what-commit-7-turned-out-to-be).** Only the
self-enrolment AUTO-APPROVE branch refuses a pre-enrollment connection; the
route that works is request → approve on the same connection, because
`isAuthorized` grants a null enrollment id full access, so such a client is its
own approver. Proven end to end against a live atServer, with the atServer's
own "authenticated as the owner" refusal as the control. **What 7 must get
right**: sibling clones need distinct device names, because
`preventDuplicateEnrollRequest` runs on this path.
`enroll_verb_handler.dart:406` gates the self-enrolment auto-approve on
`authType == AuthType.apkam`, and a pre-enrollment client authenticates with
the flat `at_pkam_publickey`, which sets `pkamLegacy` and a null enrollment id
— so it cannot enter that branch at all, and :410-414 refuses a null id
outright. 7 IS a client-only item.

**Two live tests moved with 1-3, both re-fixtured rather than weakened**:
`self_enrollment_retrofit_live_test.dart` pinned the retrofit’s key package as
RS256 at pqActive, which was the rsa2048 hardcode; `apsk_server_side_test.dart`
healed a legacy-shaped enrolment, which is exactly the mint 3 removes — its
enrolment now authenticates post-quantum, which is the only shape the heal path
still serves.

✅ **Rulings 67, 113 and 126 are all amended in place**, each in the commit that
changed it, and each marked AMENDED in the ledger index.

**Commit 7 was the largest and least specified**, and it was right about that:
what it actually needed was a measurement, not a session — the atServer change
it was waiting on did not exist.

**What actually proves 5, and what does not.** ⛔ **The CLI pack is NOT a
differential for it.** `tests/at_onboarding_cli_functional_tests` ran green —
19 tests, 1m34s, all five files, the approve path exercised — but the 45-second
bound added on 2026-08-29 means it would have passed before the deletion too,
just slower. It establishes **no regression**, not that the deadlock is gone;
and the barrier's own warning is absent because the code that emits it was
deleted, which is a control drawn from the property under test. **The proof is
the unit guard**: `pq_client_bootstrap_test.dart`'s *"a signer answers while a
startup step is still parked"* parks the sweep so the startup is genuinely
mid-flight and has not reached the mint, then asserts a signer returns.
Mutation-proven — making `signingKeys` await anything reddens exactly that
test, quoting its own reason, with the other sixteen green.

✅ **The e2e pack IS run**: 62 passed at base port 26000, including commit 6's
`long_lived_atsign_guard_test.dart` change. ⛔ **Its approvers need NO posture
change** — measured, not assumed: the three retrofit files pass with their
approvers at `PqPosture.legacy`, because those enrolments carry their own
wrapped key and the refusal keys on the absence of one. Moving them breaks
`TestPreferences`' one-posture-per-atSign memoisation, which is what a first
attempt did.

✅ **7, as built.** `_settleEnrollmentIdentity` drops its `enrollmentId == null`
return; `AtClientImpl.firstEnrollmentIdentity()` names what a client with no
enrollment asks to be, with a **per-device** device name rather than the bare
`firstDevice` the design named — measured, the bare constant leaves every
sibling clone after the first refused at every start for ever. at_auth approves
its own `pending` response when the **session** carries no enrollment id, which
is the discriminator because `pending` also means an atServer too old to
auto-approve an APKAM retrofit, and that one keeps its deny-and-throw. A third
change: an `on Error` clause beside the `on Exception` one, because the
method's dartdoc promises nothing is fatal while `retrofitIdentity` throws
`ArgumentError`. ⚠️ **`AtOnboardingPreference` inherits the `pqReady` default,
so every `at_activate` command now self-enrols a pre-enrollment atSign and
rewrites its `.atKeys`** — ruled INTENDED by gkc, and two legacy-shaped groups
of the CLI pack were re-fixtured at `PqPosture.legacy`.

### 14.30 A content notification can outrun the key that opens it

Found 2026-08-16 writing UC-A3.4's self direction live
([decisions 106](decisions.md#106-a-notification-that-outruns-its-key-is-dropped-not-parked-2026-08-16)).
A notification whose decryption needs an nskey private the receiver has not yet
**filed** is **dropped and never retried**, while the private is filed a
fraction of a second later and the envelope stays on the atServer for
`envelopeTtl`.

**Cause, measured 2026-08-17.** The push is built and on time: approval conveys
the private (`EnvelopeEnrollmentConveyance`), and the receiver reads and deletes
both of its `__ssenv` envelopes. What is missing is the **wait** — `AtClientImpl`
fires `unawaited(_pqBootstrap!.startup())`, and
`PqClientBootstrap._collectConveyedKeys` (*"the only route by which a conveyed
nskey private reaches the keyfile"*) is that startup's second step. A client is
handed to its caller before its conveyed privates are filed. Drop at `12.703`
with `no nskey private held`; the ring's read-miss self-heal fired at `12.819`,
**116 ms too late**.

✅ **RULED 2026-08-17 (gkc), and BUILT** — see
[106.5](decisions.md#1065-ruled-park-and-re-drive-not-readiness-at-the-hand-back-2026-08-17).
Direction 2 was not taken on its own: awaiting `startupComplete` closes only the
startup window, and a private conveyed while the client is already running still
races.

**What shipped.** `NskeyPrivateUnavailableException` carries
`(owner, namespace, nskeyKid)` so the park has a key that is not a message
string; `SignalsPrivateFiling` — implemented by `PublishedNskeyKeyRing`,
emitting from `NskeyPrivateFiling` **after** the material is readable — is what
releases it; `CryptoConfig` now carries the `keyRing` so the notification
service can reach the signal without depending on which providers are
registered. The park is bounded by `maxParked` and `parkTtl`, and every
eviction logs at `warning` naming the notification, because a held message
nothing re-drives is the same data loss with a longer fuse.

Unit cover: `notification_park_test.dart` — five rows, including the two
controls that keep it honest (a failure no filing can fix is dropped rather
than parked, and a filing for a *different* generation releases nothing).
Removing the park reddens three of them, each quoting its own reason.

**Four vacuous live attempts preceded the proof below, and they are kept because
each one is a trap worth not re-entering.** ⚠️ This paragraph used to end "Not
proven live, and a live proof needs something that does not exist yet" — that
was true when written and is now false; the whole chain is proven live, further
down. What the attempts establish:

1. **Minting the nskey *after* the enrollments** — intended to leave the
   receiver without the private. It leaves the *sender* without a published
   nskey too, so the send falls back to `legacy`, the receiver opens it
   trivially, and the run is green with the park never entered.
2. **Minting before, and not awaiting the receiver's `startupComplete`** — the
   originally measured shape. Still green with `parkedTotal == 0`: the test's
   own positive control (waiting for the monitor's stats notification to prove
   the monitor is live) takes seconds, and the receiver's startup finishes
   inside it. **The setup closes the very gap the test exists to open.**

The window is ~116 ms and sits between an `unawaited` startup's second step and
a notification, so no arrangement of ordinary test setup reliably lands inside
it. ⚠️ **Both runs would have been recorded as live proof but for
`NotificationServiceImpl.parkedTotal`**, a cumulative counter added precisely so
that "it arrived" cannot be mistaken for "it was parked and released".

3. **A `holdBeforeStore` seam on `NskeyPrivateFiling`**, so the window is held
   open rather than raced. ⚠️ This entry used to end "reverted unexercised …
   committing it would have added a test affordance to production crypto that no
   test uses". It **was** reverted at the time, for that reason — and once the
   `legacy` cause below was found it went back in and is now exercised by the
   live row (`nskey_private_filing.dart`, used at the live test's hold). The
   seam is in the tree; only the attempt that could not use it was discarded.
4. **Reordering so the receiver enrols before the second namespace is minted
   and the sender after** — on the hypothesis that `currentPublic` being
   local-first hid the new namespace from the sender. Also still legacy.

✅ **THE PARK IS PROVEN LIVE**, in
`tests/at_functional_test/test/nskey_park_and_redrive_live_test.dart`. A real
notification, sealed `at/nskey/XWING/AES/GCM` to a generation the receiver
genuinely does not hold, is **held rather than dropped**:

```
Parked notification @alice🛠:parked….nskeyparkb…
```

The window is made deterministic by `NskeyPrivateFiling.holdBeforeStore`, a
test-only hook: the race is ~116 ms wide and four earlier attempts to catch it
by timing all passed while never entering the park.

⛔ **What made those four vacuous, so nobody repeats them.** The era default is
`readsNskeyWritesLegacy` — it reads the nskey path and **writes legacy** — so a
`notify` that does not pass `cryptoProviderId: symmetricAesGcmCryptoProviderId`
goes out legacy and the park is never reached. UC-A3.4's test passes it on one
line. Four live runs were spent not reading that line; one grep would have
answered it. The other dead ends: minting the nskey after the enrollments
(starves the sender too), and installing the hold after the second namespace is
minted (the receiver has already filed by then).

**Two real defects fell out of the live work, both invisible to unit tests:**

1. **The filing signal resolved the wrong config.** `_listenForFilings` read
   `getPreferences().crypto.keyRing` — the *raw* preference. An app that names
   no config gets the era default, whose ring the PQ bootstrap supplies, so the
   read found null and the service silently subscribed to nothing. Now via
   `CryptoConfig.forClient`, re-attempted at park time because the bootstrap
   wires the ring asynchronously. Unit tests set `crypto` explicitly, which is
   the one case where the raw read happens to work.
2. **Every client held TWO `NskeyPrivateFiling` objects.**
   `collectConveyedKeyMaterial` built its own unconditionally, so the object
   that actually files conveyed privates was not the one the ring exposes.
   Harmless while filing was write-only — both wrote the same keyfile — but the
   moment a filing gained an observable event, the emitter was unreachable.
   Measured: `hasListener=false` on the announcing object while three clients
   had each subscribed successfully to a different one. The bootstrap now passes
   `ring:` through and the sweep files through the ring's filing.

✅ **THE WHOLE CHAIN IS PROVEN LIVE.** The run shows it end to end:

```
Parked notification @alice🛠:parked…
handleRequest kind=request          (the holder sees and answers the ask)
Filed the nskey private nskeyparkb…:__nskey.b195…
re-driving 1 parked notification(s)
```

and the notification is delivered **decrypted**. Getting there took three more
defects, none of which a unit test could reach:

1. **`PairwiseSecretSharing.startListening()` had no production caller**, and
   `_handleRequestPayload` — which answers another enrollment's request — is
   reachable **only** from `sweepOnce`. So a client's only sweep was the one at
   its own start, a request arriving later was seen by nobody, and **no
   read-miss self-heal could complete for anyone**. `PqClientBootstrap` now
   starts the listener and `stop()` tears it down.
2. **A declined request returned silently.** A holder that refused logged
   nothing, so "nobody answered" was indistinguishable from "everybody
   declined". Now `warning`, naming both sides. Fixing the instrument first is
   what made the next step findable.
3. **The read-miss heal asked and never filed the answer.** This is the one that
   mattered. `_askForMissingPrivate`'s dartdoc claimed *"the answer is filed by
   the arrival path so a later read finds it"* — and **there is no such arrival
   path mid-session**: nothing subscribes to `receivedSecrets` to file an nskey
   private, and `NskeyPrivateFiling.filePending` says so itself (*"a private
   that arrives after this runs is filed at the next start"*). Two dartdocs in
   one subsystem contradicted each other and the ring's was wrong. The heal now
   waits for the answer and files it, exactly as the startup path already did.

⛔ **What made four earlier live attempts vacuous, so nobody repeats them.** The
era default is `readsNskeyWritesLegacy` — it reads the nskey path and **writes
legacy** — so a `notify` without
`cryptoProviderId: symmetricAesGcmCryptoProviderId` goes out legacy and the park
is never reached. UC-A3.4's test passes it on one line. Also dead: minting the
nskey after the enrollments (starves the sender too), and installing the filing
hold after the second namespace is minted (the receiver has already filed).

The window is made deterministic by `NskeyPrivateFiling.holdBeforeStore`; it is
~116 ms wide and every attempt to catch it by timing passed while never entering
the park. `parkedTotal` is asserted so a run that wins the race cannot pass
quietly.

### 14.31 A refused watermark write permanently disables the monitor

`Monitor.stayConnected` calls `getLastNotificationTime()` **before** issuing
`monitor:`, and its first-call branch **writes** a seed record
(`local:lastreceivednotification.<ns>@<atSign>`). Under
`disallowLegacyEncryption` that put throws `LegacyEncryptionRefusedException`,
the exception escapes to the connect handler, and the monitor closes and
retries with backoff — **forever**. The client is silently deaf. The same
refusal hits `lastreceivedservercommitid`, the sync watermark.

That these writes are refused is **already known and owed to R-2** —
`PqPosture.pqActive`'s own dartdoc names "the sync and notification
watermarks" among them. What is new is the blast radius: one refused internal
write does not fail one write, it takes the notification listener out
altogether.

**Measured** on `nskey_self_notify_live_test.dart` at `56f69577a`, three arms,
same rig:

| arm | `refusing to encrypt` | test |
|-----|----------------------|------|
| both enrollments `migration` | 0 | pass |
| receiver `postQuantum` | 10 | pass |
| both `postQuantum` | 18 | fail |

⚠️ The receiver-only pass is timing luck — ten refusals happened in it too. It
is not evidence that one PQ client is safe.

⛔ **Not PKAM**, which is where three earlier guesses went. Every enrollment
authenticates `rsa2048` under both postures, with no signing-algorithm
resolution warnings: `signingAlgoOf` prefers the key-material resolution, and
the posture moves the *signing* key, never the authentication key.

✅ **DONE 2026-08-17.** It was six related defects, not one, and the diagnosis
above named the symptom rather than the cause. Ruling
[107](decisions.md#107-a-local-record-is-not-encrypted-and-the-legacy-refusal-exempts-it-2026-08-17)
carries the measurements; what shipped:

1. **A `local:` record no longer goes through the shared-data crypto path.**
   `_putInternal` and `PutRequestTransformer` skip it on `atKey.isLocal`. Such a
   record is never synced and the keystore encrypts it at rest, so value-level
   encryption protected nothing — while every post-quantum provider declines a
   local key, making *every* local write a legacy write by construction.
2. **`disallowLegacyEncryption` exempts `isLocal`.** It was refusing a provider
   **id**, not an exposure: for these keys "legacy" is `SelfKeyEncryption`,
   AES-256-CTR under a key that never leaves the device. A *synced* self key
   reaches the same class and is deliberately still refused.
3. **The SDK's own watermark writes pass `shouldEncrypt = false`** — the third
   layer, matching how the refusal is already checked at both selection and
   encryption time.
4. **`Monitor` no longer dies from it.** The watermark read has its own guard
   rather than sitting inside the connect `try` alongside four other
   operations, and a connect failure that is not a `SocketException` logs at
   `warning`, not `info`.
5. **The sync watermarks are guarded, and no longer mask.** The pull cursor is
   written in a `finally`, where a throw *replaces* the in-flight exception —
   so a failed cursor write was reported instead of whatever broke the sync.
   Extracted as `persistPullCursor`, whose contract is that it never throws.
6. **The notification watermark drops the payload and the metadata blob.** All
   twelve fields were stored and one is read. Older records still read back
   unchanged, so nothing migrates.

**Rails at the fix:** at_client unit **1386 (2 skipped)**, `dart analyze lib
test` exit 0 / 351 info, `dart analyze test` in `at_functional_test` exit 0 /
193 info. Twelve new tests, each with its break-it mutation run and confirmed
red *for its own stated reason*.

⚠️ One of those mutations found a defect in the tests rather than the product:
guarding `setAndGetSkipDeletesUntil` made a **stub-arity mismatch invisible** —
`sync_service_test.dart` stubbed `put(any(), any())` while production had begun
passing `putRequestOptions:`, so mocktail returned null, the write failed, the
new guard swallowed it, and the test reported success while persisting nothing.
It now verifies the call and its arguments.

⚠️ **This section used to claim a second half was still owed** — "namespace-less
keys that are not local, a legacy recipient's `shared_key.*` most obviously, are
still refused under the posture". That was wrong: nothing routes a
`shared_key.*` through the refusal, so it can never be refused. Closed as
[14.33](#1433-closed-the-shared_key-refusal-was-never-reachable).
The one namespace-less write that genuinely is refused is
[14.35](#1435-notificationservicesend-throws-away-the-namespace-it-was-given).

### 14.32 A `primary` client's ML-DSA signing key is not visible to its verifiers

An approver built `pqActive` (so `dataSigningKeyAlgorithms = {mldsa65}`)
conveys correctly — both `__ssenv` envelopes are written — and the
receiving enrollment refuses every one of them:

```
the envelope is signed under "ML-DSA-65" and the published _apsk advertises
"rsa2048" — no algorithm in common, so there is no signature here this key
can check
```

`waitForApproval` then times out at 30s with *"No conveyed apkamSymmetricKey
arrived … the approver is running a client that does not convey"*, which names
the wrong side: it conveys, and what it wrote cannot be verified.

The approver is the atSign's own client, so it has **no enrollment id** and
mints under the `primary` pseudo-enrollment. It does mint and does try to
publish — `Minted mldsa65 signing key(s) for primary; publishing before
filing`, then `publishPublicSigningKey: what is published is not what this
client holds - republishing` — and `enroll:update` is sent **zero** times,
correctly, because there is no enrollment record to update. Yet a verifier
reading `public:_apsk.primary.a.__e@alice🛠` still saw `rsa2048` throughout the
30s.

⛔ **The transport question is ANSWERED, and the answer is no — do not
re-derive it.** This entry used to say the one open question was "by what
transport does the `primary` republish reach the atServer? A local-first put
reaches it only when sync gets round to it … a race by construction." Read
2026-08-17: **every leg of this path is remote-first.**

| leg | where | routing |
|-----|-------|---------|
| the writer's pre-read | `apkam_signing.dart:56` | `useRemoteAtServer = true` |
| the republish itself | `apkam_signing.dart:73` | `useRemoteAtServer = true` |
| all five verifier reads | `pq_signing_chain.dart` 224, 272, 403, 465, 637 | `useRemoteAtServer = true` |

So there is no value-and-pointer-on-different-transports race here, and no fix
should be designed around one.

**Also ruled out by reading, not by measurement:** signing and advertising
cannot drift on this path. `EnvelopeSigning.wrapAndSign` resolves
`await signingKeys` (`envelope_signing.dart:56`) and the advertisement is
composed from the same getter, which is what `signingKeys`' own dartdoc claims
("what signs and what is advertised are one rule and cannot drift apart").

**The cause, measured 2026-08-17 — it is a CLOBBER, in order, both writes
remote.** The arm was re-run with the approver built `postQuantum`, and the
atServer's own log for `@alice🛠` was read rather than the client's account of
it. The record starts absent (`AT0015 … does not exist in keystore`) and then
takes **four** updates:

| # | what the update wrote |
|---|-----------------------|
| 1 | a bare RSA public key (`MIIBIjANBgkqhkiG9w0B…`) |
| 2 | a bare RSA public key |
| 3 | **`{"v":1,"keys":[{…,"alg":"mldsa65",…}]}`** — the mint's republish |
| 4 | **a bare RSA public key** — overwrites 3 |

So the ML-DSA advertisement *is* published, and is then overwritten by a later
writer with the RSA fallback. A remote read taken **after** both republishes
returned the bare RSA key, which is what the verifier then refuses against for
the whole 30s. Nothing here is a transport problem; the final state is simply
the wrong value.

**The mechanism, confirmed by instrumenting `publishPublicSigningKey` and
re-running.** Every call logged what it held and what it was about to write:

| # | caller | `heldSigningKeys` | `value` passed in? | writes |
|---|--------|-------------------|--------------------|--------|
| 1 | `AtClientSecretSharing` | `[]` | no | bare RSA |
| 2 | `AtClientSecretSharing` | `[]` | no | bare RSA |
| 3 | `SigningKeyMinting` | `[]` | **yes** | **`mldsa65` JSON** |
| 4 | `AtClientEnvelopeSigner` | `[]` | no | bare RSA |

**`heldSigningKeys` is empty at all four**, so the minted signing key never
reaches the keyfile for `primary` at all. `signing_key_minting.dart:287` — the
only call that passes `value:`, and guarded by `atLookUp?.enrollmentId == null`
— advertises the minted key by handing the value in directly, which is what
"publishing before filing" means. Every other caller composes from
`publicSigningKeyValue`, reads an empty keyfile, falls back to the APKAM
authentication key (RSA), and publishes that over the mint's advertisement.

⛔ **STOP — this is [ruling 102](decisions.md#102-an-_apsk-fallback-value-never-replaces-a-real-advertisement-2026-08-15),
already measured and already ACCEPTED.** `_publish`'s own dartdoc
(`signing_key_minting.dart` ~252) describes this exact sequence — "a concurrent
`publishPublicSigningKey` … sees no signing key, falls back to the APKAM
**authentication** key, and overwrites: measured, a PQ-native enrollment's
ML-DSA array replaced by a bare RSA string" — and records that **three guards
against it were built and all three broke the live enrollment path.** It warns
anyone tempted to try a fourth that "never drop an advertised key" cannot be
stated over `public:_apsk.primary.a.__e`, which no single client owns.

**So the record-level guard is a re-derivation. Do not build it without
re-opening 102.**

⚠️ **What is NOT yet established, and what an earlier version of this entry
wrongly asserted.** It claimed "it is not a timing window … the keyfile is empty
for the whole run". The evidence does not support that: `_file` **is** called,
at `signing_key_minting.dart:167`, immediately after `_publish`, so the empty
keyfile at all four calls is equally consistent with all four falling *inside*
the publish-before-file window — which is exactly what 102 describes. The
timeline is 20 ms wide:

```
07.117  Minted mldsa65 … publishing before filing
07.119  SigningKeyMinting   held=[]  -> writes mldsa65 (value: override)
07.155  … republishing
07.175  AtClientEnvelopeSigner held=[]  -> writes bare RSA
07.200  … republishing
```

**Ruling 102 has been re-opened on this evidence** — see
[102.1](decisions.md#1021-the-race-is-measured-and-the-price-it-was-accepted-at-was-wrong-2026-08-17).
Two of its sentences were false and are corrected there: the race **is**
measured, and reaching it needs **no** application call racing `startup()` —
the ordinary approver flow does it every run. More importantly the *price* was
wrong: 102 accepted "one process lifetime of refused envelopes", where the
measured cost is that **a `postQuantum` approver cannot approve an enrollment
at all**.

⛔ **That does not revive the three guards.** Guard 3's finding stands: the
demotion rule cannot be stated over `primary`, a record no single client owns.

✅ **The filing works, so this is 102's window and nothing else.** Logging
`heldSigningKeys` immediately after `_file` returns gives `[mldsa65]`, with the
mint's `io` and `atClient.atKeysIo` the same instance. The keyfile does hold the
post-mint state; `AtClientEnvelopeSigner` simply read before the filing
completed.

✅ **DONE 2026-08-17 — fixed by serialising this process's `_apsk` writes**,
ruled and built as [102.2](decisions.md#1022-the-in-process-window-is-closed-by-serialising-the-writers-2026-08-17).
`serialiseApskWrite` chains every `_apsk` write one client makes, and the mint
holds it across publish, file and retire together, so a writer arriving mid-mint
composes after the filing and finds nothing to change. It states in-process-only
and nothing more — a second client in another process is still 102's accepted
window. Re-entrancy is handled by splitting `publishPublicSigningKey` (acquires)
from `publishPublicSigningKeyLocked` (does not).

**Proven live on the arm that had never passed:** updates to
`_apsk.primary` go 4 → 2, the final value goes bare RSA → the `mldsa65` array,
`no algorithm in common` goes 2 → 0, and the test goes fail → pass. Unit cover
in `apsk_write_serialisation_test.dart`, whose ordering test reddens on the
exact interleave when the lock is removed.

⚠️ This is **not** [14.31](#1431-a-refused-watermark-write-permanently-disables-the-monitor).
That one is a refused internal write killing the monitor; this one is an
advertisement a verifier cannot see. Both surfaced from the same posture and
they have nothing else in common.

### 14.35 `NotificationService.send()` throws away the namespace it was given

`send()` takes a namespace as a parameter, builds a key string from it, and then
recovers the namespace by re-parsing that string
(`notification_service_impl.dart:578`):

```dart
final String key = '$to:$namespace$atSign';
final AtKey atKey = AtKey.fromString(key);
atKey.metadata.namespaceAware = false;
```

`AtKey.fromString` splits at the last dot, so the round trip is lossy in two
different ways. Measured, both arms, against a client under the postQuantum
posture:

```
send(namespace:"wavi")       => THREW LegacyEncryptionRefusedException
send(namespace:"buzz.wavi")  => selected at/symmetric/AES/GCM
```

A **single-segment** namespace parses to `namespace = null`, so every
post-quantum provider declines it (`canHandle` is `!isLocal && namespace != null
&& namespace.isNotEmpty`), the fallback is legacy, and the flag refuses it. A
**dotted** namespace parses to `key = "buzz", namespace = "wavi"` — it seals,
but to an nskey scoped to `wavi` rather than to the `buzz.wavi` the caller
named.

`send()` is the only write path that can reach this, because it is the only one
that bypasses the namespace defaulting every other path applies before
encrypting — `at_client_impl.dart:981` and `:1252`
(`atKey.namespace ??= preference?.namespace`) and
`notify_request_transformer.dart:122` (`ak.namespace ??= atClientPreference.namespace`).
`send()` encrypts inline and hand-builds its own `notify:` command string, so it
touches none of them. `AtRpc` sets `..namespace = baseNameSpace` explicitly and
goes through `notify()`, so it is unaffected.

**The fix, ruled by gkc 2026-08-17: the parameter is `<id>.<namespace>` and is
poorly named — that is the root of it.** The id is the first segment and the
namespace is the remainder, so `send()` splits at the **first** dot and sets
both `AtKey` fields itself instead of letting `fromString` do it. `namespace` is
deprecated in favour of `idAndNamespace`; a name with no interior dot, or with
either half empty, throws `ArgumentError` at the call site.

⚠️ **An earlier draft of this row recorded a one-line fix — "set
`atKey.namespace = namespace`" — and that was WRONG.** It would have broken
every `send()` that works today. The ciphertext binding is computed over
`'${atKey.key}.${atKey.namespace}'`, deliberately split-invariant so writer and
reader agree, and setting only the namespace changes the joined name. Measured:

```
                     sender          receiver (parses the wire)
today                "buzz.wavi"     "buzz.wavi"        match
+ namespace only     "buzz.buzz.wavi"  "buzz.wavi"      MISMATCH — nothing decrypts
+ namespace, key=""  ".buzz.wavi"    "buzz.wavi"        MISMATCH
first-dot split      "a.b.c"         "a.b.c"            match
```

The first-dot split holds for every case tried (`wavi`, `buzz.wavi`, `a.b.c`,
`id.foo.bar.my_app`) precisely because the join is split-invariant: the sender
cutting at the first dot and the receiver at the last produce the same name.
The wire key is unchanged, so this is not a cross-version break; what changes is
that the content key is conveyed at the level the caller named, and a receiver
that has not yet got it parks and re-drives
([14.30](#1430-a-content-notification-can-outrun-the-key-that-opens-it)).

`send()` is public, documented and not deprecated, and two example programs use
it (`example/bin/notifications.dart`, `example/bin/dockerstats_publish.dart`) —
both with dotted namespaces, so both take the wrong-scope arm rather than the
refusal.

### 14.36 `send()`'s command is hand-rolled where a tested builder exists

`send()` writes its own `notify:` command into a `StringBuffer` rather than
using `NotifyVerbBuilder`, which is what every other notification path goes
through. It is the duplication that let
[14.35](#1435-notificationservicesend-throws-away-the-namespace-it-was-given)
happen: the builder path resolves a namespace before encrypting, and `send()`
never reached it.

The swap is nearly free, but not free. Measured, same inputs:

```
hand-built today   notify:id:X:ttln:900000:isEncrypted:false:@bob:a.b.c@alice:payload
NotifyVerbBuilder  notify:id:X:notifier:SYSTEM:ttln:900000:isEncrypted:false:@bob:a.b.c@alice:payload
```

Byte-identical **except** `:notifier:SYSTEM`, which `buildCommand` writes
unconditionally. So this is a wire change, not a refactor, and it does not ride
along with a behaviour fix — it gets its own commit and its own functional-pack
run. The argument that it is safe (every `notify()` call already sends that
token, so the atServer sees it constantly) is an argument, not evidence.

⚠️ **`useAtKeyToString = true` is required.** With it false the builder writes
`:${atKey.key}`, and since 14.35 the name is split across `key` and `namespace`,
so the wire key would become `@bob:a@alice` — measured. `atKey.toString()`
yields `@bob:a.b.c@alice` under either `namespaceAware` setting.

**Built 2026-08-17.** The command is pinned as a raw literal rather than by
`contains` fragments — a wire shape is frozen, and an intended change has to
edit the pin, which is the review. A `contains` check would not have noticed
`:notifier:SYSTEM` arriving.

⚠️ **`send()` had NO live coverage at all, in either direction** — the pack's
168 tests never called it, so the first pack run after this change proved only
that nothing else regressed. `:notifier:SYSTEM` being safe rested on every
`notify()` already sending it, which is an inference, not an exercise of this
path. `atclient_notify_test.dart` now drives `send()` live: it asserts the
stored notification's key is the *whole* name (the wire half, which a builder
writing only `atKey.key` would truncate) and that the body arrives decrypted at
the recipient.

⚠️ **The architecture guard had to move with it, and the direction matters.**
`architecture_guard_test.dart` required `notification_service_impl.dart` to
mention `toAtProtocolFragment`, which the file no longer does — the builder
calls it. Keeping that assertion would have forced the hand-rolled command back,
so the guard now asserts the file does **not** contain `'notify:id:`. That is
what the guard was always for: not the presence of a name, but the absence of a
rival serializer. Verified against the previous commit, where the pattern
appears once.

### 14.40 at_client publishes as a minor, and the heading now says so

✅ **RESOLVED 2026-08-20. The tree already moved and this body did not say so
for two days.** `packages/at_client/pubspec.yaml` is `version: 3.15.0` and its
`CHANGELOG.md` opens `## 3.15.0` — a minor, which is what a source-breaking
entry needs. Verify rather than trusting this line:
`grep -m1 '^version:' packages/at_client/pubspec.yaml && head -1 packages/at_client/CHANGELOG.md`

What it was: raised 2026-08-18 by the `0x01` removal, which added a **BREAKING**
entry under an in-progress `## 3.14.1` heading. A patch version carrying a
source-breaking change was the conflict; the entry itself was correct and
stayed. ⚠️ The heading above read "at_client's in-progress heading is a patch"
until today, which a reader would take as the current state.

⚠️ **The question got bigger on 2026-08-19, not smaller.** 14.39 added four more
**BREAKING** entries under the same `## 3.14.1` heading — `PqPosture` replacing
`ReleasePosture`, `SigningRollout` deleted, `disallowLegacyEncryption` losing
its constructor argument, and `inUseSigningAlgorithms` renamed — plus a
**BREAKING** `--posture` entry under at_onboarding_cli's in-progress `## 1.17.0`.
So this is now two version questions, not one. The blast-radius argument is
unchanged and still bounded: none of that surface is published (at_client 3.14.0
on pub.dev carries no `ReleasePosture`, no `SigningRollout` and no
`disallowLegacyEncryption`), so no released consumer breaks — it remains a
numbering question.

The break is real: `SecretSharingAlgos.xWingHpke` is gone, `suites` and
`openableSuitesFor` no longer name it, and the `suites` list emitted on
`enroll:request` narrows. What it costs is bounded by the same argument
[decisions 109](decisions.md#109-at_chops-360-stays-a-minor-no-major-bump-for-this-release-2026-08-18)
makes for at_chops — the substrate is `@experimental` and its only consumer is
this repository — so this is a numbering question, not a blast-radius one.

⛔ **Not acted on deliberately.** Version bumps are gkc's call and the standing
rule is to fold entries under the in-progress heading rather than open a new
one. Recorded here so the conflict is not discovered at publish time.

### 14.41 What the first CI runs on the spike branch found

CI had never run on `gkc-pq-d1-spike` and structurally could not: both
workflows trigger only on `trunk`. Dispatched manually 2026-08-20 through
`workflow_dispatch`, on both `at_client_sdk.yaml` and `at_libraries.yaml`.
Everything below is from those runs plus the re-runs after each fix.

**Three CI-only defects were found and fixed**, none of them in library code:

| Fixed | What it was | How it is known to be fixed |
|-------|-------------|------------------------------|
| The VE image | Three jobs took the compose default `vip`; the post-quantum tests need a trunk-tracking atServer | `functional_tests` green on both channels against `dev_env` |
| The format gate | 95 files did not satisfy `dart format . -o none --set-exit-if-changed` in at_client and at_client_flutter | `unit_at_client` and `unit_at_client_flutter` went red to green on both channels |
| The e2e readiness step | `supervisorctl status` exits non-zero whenever ANY program is not RUNNING, and `pkamLoad` is deliberately `STOPPED`. As the last command of the step it failed a container that was in fact healthy | `legacy_server_tests` green for the first time; `pqe2e_tests` reaches its tests and runs 16 of 17 |

⚠️ **The same readiness bug is still in `tests/at_end2end_test/runLocal.sh`**,
where the loop cannot succeed either — so every local e2e run silently waits
the full 60 seconds before doing anything. Harmless, and worth removing.

**All four are fixed.** ⚠️ **"CI is green" is a claim about ONE workflow at ONE
commit, so say which:** `at_client_sdk.yaml` run **32392240064**, 11 of 11, on
`f24ee3ab6` — the head with `origin/trunk` merged in, covering at_commons #2168.
`at_libraries.yaml` last went green on a **different** commit, and docs commits
have landed since, so **no run covers the current head**. Re-derive before
repeating the claim; the command is in the re-derivation block.
wrong image. A convergence race remains, recorded below as a rate and owed in
[14.43](#1443-the-functional-suites-convergence-race). This section said "three" until
2026-08-20, when a fourth was found in `at_libraries`' matrix that had never
been recorded here at all — and that fourth turned out to be the cheapest of
the lot, a CI step running the wrong image.

⚠️ **Only ONE of the four was a product defect.** Rows 2 and 4 were harness
assumptions that had been holding by luck — an environment variable that
happened to survive, a file order that happened to be favourable — and both
failed deterministically the moment the luck changed. Row 1 was the real bug. None was the image, and none was a
flake: gkc ruled out infrastructure on 2026-08-20.

1. **`notify_test.dart` — FIXED 2026-08-20. A closed connection held the
   request mutex for 30 seconds.** `end2end_tests` was 36 of 37.

   Nothing to do with notifications, and nothing to do with the monitor. The
   monitor start and the teardown 62 ms later — which this row used to lead
   with — are ordinary atSign-switch behaviour and were a red herring; so is
   the test's name, which promises listening it never does (it reads back with
   `notifyList`). What actually happened, from the local log:

   ```
   12:44:59.882  @bob's PqClientBootstrap sends a verb, and waits for the reply
   12:44:59.885  the test switches atSign, so AtClientImpl.stop() destroys
                 @bob's socket 3 ms into that wait
   12:45:00.468  the test switches back to @bob and calls notifyList
   12:45:29.885  the test times out, 30 s after it started
   12:45:29.886  the abandoned read gives up and releases the mutex, one
                 millisecond too late
   ```

   `OutboundMessageListener.read` had no way to notice that its connection was
   gone: it woke only on a queued response or a deadline, so it sat out the
   full transient budget. `AtLookupImpl._process` holds `requestResponseMutex`
   across that read, and `AtClientImpl.create` memoises one client per atSign —
   so switching back to @bob handed the test the same AtLookupImpl, and its
   first verb queued behind a response that could never arrive.

   **Why it was a regression rather than a long-standing bug:** the defect is on
   trunk too, but the transient budget there is the parameter default of
   **10 s**, where this branch takes `AtNetworkTimeouts.effectiveDefault` —
   **30 s**. Ten seconds fits inside `dart test`'s 30-second per-test timeout;
   thirty does not. ⚠️ `AtNetworkTimeouts`' own dartdoc records that
   `defaultResponseBudget`'s 90 s "preserves the long-standing default … so
   adopting this changes no behaviour" — true of the whole-response budget, and
   silent about the transient one, which tripled in the same change.

   Fixed in at_lookup: every close routes through one place that fails the
   pending read first, and the caller gets a `ConnectionInvalidException`
   naming the closed connection instead of an `AtTimeoutException` pointing at
   the atServer. Pinned by four arms in
   `packages/at_lookup/test/socket_delivery_test.dart` — measured at **3003 ms
   against a 3000 ms budget before, immediate after** — the fourth holding the
   line that a response already parsed is still returned.

   Re-run it rather than trusting this row:

   ```bash
   cd tests/at_end2end_test && ./runLocal.sh 26000 test/notify_test.dart
   ```

   Green twice locally on 2026-08-20, and the second run carries the proof that
   the fix is what did it: `Connection closed with a request in flight` at
   13:01:25.009403, 211 microseconds after `AtClientImpl (@bob) stop()`, where
   the same request previously took 30.003 seconds. **`end2end_tests` is then
   green in CI** on run 32369016084 — so this is confirmed against the @ce2e
   atSigns too, not only the virtualenv.

2. **`nskey_recipient_not_ready_test.dart` UC-A4.2 — FIXED 2026-08-20. The
   control borrowed another file's side effect.** `pqe2e_tests` was 16 of 17,
   red on `control: readiness must be able to say yes, or its "no" carries no
   information` — the test correctly refusing to certify its own "no".

   The control asked whether `@bob` was ready for the **shared** `e2e_test`
   namespace. Nothing in that file made him ready: the e2e preferences set no
   crypto config and no posture, so an e2e client is legacy by construction and
   never mints an nskey on its own. It answered "yes" only when one of
   `era_default_read`, `nskey_notify` or `nskey_cross_atsign` had already
   minted @bob's `e2e_test` key.

   ⚠️ **`dart test` does not order files alphabetically, and the order is not
   stable between runs.** CI ran this file **first** of five; a later local run
   of the same directory ordered them
   `nskey_multi_enrollment, era_default_read, nskey_cross_atsign, nskey_notify,
   nskey_recipient_not_ready`. So the row was deterministic in CI and invisible
   in a directory run that happened to schedule it late — do not read a green
   directory run as evidence about this class of defect.

   Fixed by making the file establish every fact it asserts: it moves onto
   `ConcurrentClients` (so @bob can be brought up without the singleton tearing
   alice's client down) and @bob mints a **run-unique** warm namespace as the
   control's yes-case. The control still exercises the same query; it no longer
   adds a writer to the shared namespace.

   Measured, file run ALONE, both arms in one session — which is the arm that
   discriminates, since a directory run may schedule it late and pass either
   way:

   | arm | result |
   |-----|--------|
   | before the fix | control fails |
   | after the fix  | passes |

   Whole directory as CI invokes it (`test/pq -x legacy-server`): **17 of 17**.

3. **`end2end_test_14` — the setup is FIXED; a second layer is now visible.**

   **The setup step was SLOW, not stuck, and its budget was the framework
   default.** Measured 2026-08-20: given five minutes, all four approvals pass
   in **4:59**. Given thirty seconds they all time out. Two defects fixed:
   the step ran with `dart run`, which exits 0 even when its tests fail — so it
   went green with four timed-out approvals and the failure surfaced three
   minutes later as eight missing-keyfile errors in a different step — and the
   budget is now fifteen minutes, because 4:59 against 5:00 is a coin toss.

   ⚠️ **Sync volume is NOT a sufficient cause, and this row said it was.**
   `end2end_tests` runs the SAME four @ce2e atSigns (config23 lists the same
   set config14 does, reordered) and the SAME suite, and it is green. The
   differentiator is that `end2end_test_14` runs `enrollment_setup.dart` first.

   **The second layer, and the strongest lead on it.** With the setup passing,
   the suite reaches 34 tests instead of 12 and 18 fail, on
   `PKAM Keypair required for signing`. `AtClientImpl` has exactly **one**
   `_atKeysIo` field and it serves two jobs: the nskey private store handed to
   `PqClientBootstrap` (`at_client_impl.dart:610`) **and** the authentication
   key source in `_createAtChops` (`at_client_impl.dart:1651`), which prefers
   it over the local secondary. This branch's `test_initializers.dart` points
   that field at `<hiveStoragePath>/<atSign>.nskey.atKeys` and seeds it with an
   **empty `AtKeys()`**. A client that is not handed an `atChops` therefore
   authenticates from an empty keyfile.

   ⭐ **ROOT-CAUSED 2026-08-20, and it is the client cache key.** The
   `_atKeysIo` reading above was a wrong turn — the failing client's
   `_atKeysIo` is **null**; it takes `_createAtChops`' local-secondary branch.
   The actual chain, every link observed, and it **reproduces locally in about
   three minutes** (`enrollment_setup.dart` then `notify_test.dart` against the
   virtualenv, no @ce2e atSigns and no CI round trip):

   1. `enrollment_setup.dart` enrols an app per atSign and writes an
      **`enrollmentId` into the keyfile** — confirmed by reading
      `atKeys/@alice🛠_key.atKeys` after a local run.
   2. `testInitializer`'s apkam auth then passes that id, so the client is
      filed under `(atSign, enrollmentId)`.
   3. Tests like `notify_test.dart` call
      `setCurrentAtSign(atSign, namespace, preference)` with **no** enrollment
      id, which looks up `(atSign, null)`, **misses**, and builds a fresh client
      with no `atChops` and no `atKeysIo`.
   4. That client's `_createAtChops` falls through to the local secondary, which
      holds no PKAM key, and every verb fails
      **`PKAM Keypair required for signing`**.

   **Why it is a spike regression, mechanically.** Trunk keys the cache on the
   **atSign alone** (`atClientInstanceMap[currentAtSign]`); this branch keys it
   on **`(atSign, enrollmentId)`** via `AtClientImpl.instanceKey`. On trunk the
   bare call hits the very entry `testInitializer` created and gets the
   credentialed client. That is also why only `end2end_test_14` fails: it is the
   only job that runs `enrollment_setup` first, so the only one whose keyfile
   carries an enrollment id at all.

   ⚠️ **The change itself is right** — keying a client cache on the owner alone
   hands a caller another principal's object, and the code says so. What is
   unsettled is what `enrollmentId: null` should MEAN once an enrolled client
   exists for that atSign: return it, refuse loudly, or build the
   uncredentialed one it currently builds. **RULED by gkc 2026-08-20 and shipped in `0c79164fa`:** an
   unnamed enrollment falls back to the atSign's client when there is exactly
   ONE, and refuses naming the available ids when there are several. This
   paragraph asked for a ruling that now exists; do not go and ask for it
   again.
   It is a standalone setup step (`dart run test/enrollment_setup.dart`), not a
   test on `dart_test.yaml`'s allowlist, so its failure cascades: the 8 later
   failures all read `provided keys file does not exist`, for the keyfile the
   timed-out step never wrote. The throw is `OutboundMessageListener.read`'s
   *transient* branch, meaning `_lastReceivedTime` never moved — no bytes at
   all, not a partial response. ⚠️ **Row 1's fix does NOT close it — measured,
   not assumed.** `end2end_test_14` is still red on run 32369016084, the first
   CI run carrying the connection fix, so the shared fingerprint was a
   coincidence of symptom and the cause is a different one. ⚠️ This row used to end "It cannot be
   reproduced locally … so iterating on it costs a CI round trip", which was
   never true of the script: the blocker was `AtCredentials.credentialsMap`
   being a stub in every checkout, and the harness now seeds it from
   `AtTestCredentials`.

4. **`functional_tests_at_onboarding_cli` — a fourth red row, and it was never
   recorded here.** The non-proxy leg of `at_libraries`' matrix runs 16 of 17;
   the red is `pq_native_onboard_test.dart`'s "a CLI activation under the
   pqReady posture is PQ-native", failing PKAM for `@denise` with a
   **server-side** `AT0010-Exception: RangeError: Value not in range:
   -2881644029407446706`. Red on run 32360105692 as well, so it predates the
   connection fix. That test is new on this branch, so there is no trunk arm to
   compare against.

   **ROOT-CAUSED and fixed 2026-08-20: the job was running the published
   image.** ⚠️ This row first said "It is NOT the image, the env is set at job
   level and both matrix legs inherit it" — that was wrong, and wrong in an
   instructive way. The variable *is* set on the job, and the step ran
   `sudo docker compose up -d`; **`sudo` resets the environment**, so compose
   never saw `VIRTUALENV_IMAGE` and fell back to the `atsigncompany/virtualenv:vip`
   default in `docker-compose.yaml`. The published atServer cannot verify an
   ML-DSA PKAM signature, and its symptom is exactly this `RangeError`.

   It is the only container job in either workflow that used `sudo`; every one
   in `at_client_sdk.yaml` runs plain `docker compose` and gets its image. The
   fix drops the `sudo` and adds a step that inspects the **running**
   container and fails loudly when it is not the image the job asked for —
   because a wrong image otherwise presents as a client-side bug.

   Measured, both arms in one session, one variable changed:

   | image | result |
   |-------|--------|
   | `atsigncompany/virtualenv:dev_env` | 2 of 2 pass |
   | `atsigncompany/virtualenv:vip`     | `Pkam auth failed … AT0010-Exception: RangeError` |

   ⚠️ The earlier claim came from parsing the YAML and printing the resolved
   image per job. That measures what the *job* declares, not what *compose*
   receives — a validation of the wrong thing, and it read as thorough.

⚠️ **A fifth row, on the BETA Dart channel only, and it is a rate rather than
a kind.** `functional_tests (beta)` has failed **3 of 5** runs on 2026-08-20 —
`sync_multiple_client_test.dart` once and `pq_rollout_matrix_test.dart`'s
UC-G1.15 **twice, consecutively**. `functional_tests (stable)` is 0 of 5, and a
local full pack on stable was 177/177. (Established 2026-08-21: this window's
sync_multiple red is the SAME instance as the sixth row's below — the day's
beta runs held exactly one — so these two rows share a numerator; and it is
classified in [14.43](#1443-the-functional-suites-convergence-race).)

⭐ **This is a RACE, not a channel defect** (gkc, 2026-08-20). The rates say
so: **beta 3 red in 6, stable 1 red in 6**, and a race is what produces that
shape — the beta SDK's different timing widens the window rather than
introducing a bug. Reading it as "beta-only" was wrong twice over: stable has
now hit it too, and the framing pointed the search at the Dart channel instead
of at the window.

**Where the search has got to, and what is NOT established.** The harness's
`FunctionalTestSyncService.syncData()` waits on a LEVEL — it loops until
`localCommitId == serverCommitId` and nothing is pending — rather than on
*this test's writes having been pushed*. The only thing between a test's writes
and that check is a blind `await Future.delayed(Duration(milliseconds: 100))`.
In the local failure of 2026-08-20 it returned in **7 ms** reporting
`pending push count: 0` with the ids already equal, immediately after the test
had done three writes. ⚠️ **That is a characterisation, not a discriminator:**
a PASSING run shows a first `syncData` completing just as fast with
`pending push count: 0` too, so the pattern alone does not separate pass from
fail. Do not report it as the cause without an arm that does.

⛔ **Disproven, so nobody re-walks them.** The progress events are NOT dropped
by attaching the listener late — `MySyncProgressListener.streamController` is a
plain single-subscription `StreamController` and BUFFERS. And `syncData()`'s
`syncOutcome.complete()` on `SyncStatus.failure` — which does treat a failed
sync as done, and is a real defect worth fixing on its own — is NOT what fired
here: `SyncStatus.failure` appears **zero** times in the failing log.

Corroborating: **three of the four observed failures are notify/sync
convergence** — `sync_multiple_client_test` ("keys synced from multiple clients
converge"), `atclient_sync_conflict_test` ("notify updating of a key to
sharedWith atSign"), and UC-G1.15's cross-stage envelope verification. One
commit ran UC-G1.15 green on stable and red on beta in run 32381845256, which
is what a timing window looks like rather than a code difference. ⚠️ This row
first read "a different test each time", then "beta-only"; both were
falsified.

What the UC-G1.15 instance showed, recorded because it is the useful part:

- The failing cell was `pqActive → pqReady`, on
  `AtSigningVerificationException` — the receiver read `@alice`'s `_apsk`
  holding **exactly one key**, `kid f10e7bd62684126f`, `alg mldsa65`, and could
  not verify the envelope with it. So it is not a stale advertisement holding
  the pre-PQ key; it is an advertisement holding a key that did not sign.
- ⭐ **The same stage pair PASSES as its own test minutes earlier** (`✅
  pqActive sender to pqReady receiver`, 14:24:16) and fails inside UC-G1.15's
  nine-cell loop (14:25:53). Both go through the same `runCell`. **The variable
  is back-to-back-ness**, not the pair — the standalone tests are separated by
  framework overhead and the nine cells are not.
- Every cell overwrites `@alice`'s single `_apsk` record, and sender and
  receiver are separate processes. So a receiver can fetch an advertisement
  that a neighbouring cell published, or fetch before its own sender's publish
  has landed — the shape where a value and a pointer to it travel by different
  transports and race.
- ⚠️ The verifier's kid appears **once** in the whole 465k-line job log while
  other kids appear 4–9 times. Suggestive, NOT decisive: kids are only logged
  when a key package is, so that is a claim about the log.

**Four hypotheses are disproven, recorded so nobody re-walks them:** the
advertisement is NOT written local-first (`publishPublicSigningKey` passes
`useRemoteAtServer = true`); it is NOT the documented mint/publish race, whose
signature is an ML-DSA array replaced by a bare RSA string; there is NO mutex
contention with sync, because `SyncServiceImpl.create(atClient)` builds its own
`RemoteSecondary` and so its own connection; and the
`does not verify against its _apsk` SEVEREs are not the differentiator — they
appear **19 times in the PASSING stable log** against 17 in the failing beta
one. That last one is worth its own look some day: every functional run on both
channels logs 17–19 key-package verification failures and nothing fails.

⚠️ **A sixth row, seen once and recorded as a rate rather than a kind.**
`functional_tests (beta)` failed `sync_multiple_client_test.dart` ("keys synced
from multiple clients converge to the same value") at 176 of 177 on the
2026-08-20 16b00787c run, having passed on the 8295cea5b run an hour earlier.
`functional_tests (stable)` passed both, and both channels passed again on run
32369016084. So: **1 red in 3 beta runs, 0 in 3 stable runs** — not enough to
call it anything. Do not describe it as a flake or as a regression without
more runs. Classified 2026-08-21: this red carries shape C's signature on the
diverged key itself, and it is the SAME instance the later "3 of 5" window
counted — the day's beta runs held exactly one sync_multiple red. Evidence
and discriminators in
[14.43](#1443-the-functional-suites-convergence-race)'s shape C paragraphs.

**Four mechanisms were read and disproven** for rows 1 and 3, recorded so
nobody re-walks them: the monitor and verb sockets are *not* collapsed
(`NotificationServiceImpl` builds a deliberate fresh `AtLookUp.withSecureSocket`
and says why); `messageListener` cannot drift from `_connection` (both are
rebuilt together inside `createConnection`); a non-notification lookup *does*
notice a dead socket (`onSocketDone`/`onSocketError` call `closeConnection`
unconditionally, and the `onDisconnect` seam is additive); and Monitor's
`_notificationSubscription ??=` cannot hold a closed controller, because
`_stop()` nulls both subscriptions.

⚠️ **A measurement trap this cost an hour to.** Probing
`atsigncompany/virtualenv:dev_env` from `docker images` reads whatever was
cached locally, which can be months old — the copy on this machine was from
3 July and lacked both `mldsa65` and #2755, which produced a confident and
entirely wrong conclusion that the image ruling had been a mistake. **Pull
before probing.** The freshly pulled image is the Aug 19 build and carries
both. The contradiction that caught it was
`self_enrollment_retrofit_live_test.dart` passing "ML-DSA PKAM succeeds" on an
image just measured as lacking ML-DSA.

### 14.43 The functional suite's convergence race

**CI: beta 3 failures in 10 runs, stable 1 in 10** — measured 2026-08-20 by the
command in the re-derivation block at the end of this file, not transcribed.
Locally, **1 red in 5** packs the same day — both PRE-fix figures.
**Post-fix, local, 2026-08-21 at `112e1f740` (code-identical to the shape-C
fix commit): 0 family reds in 10 valid packs.** Eleven ran; one is excluded
as an instrument artifact with the cause confirmed by gkc — the machine
suspended mid-run (a single 46-minute wall-clock gap in the log,
08:33:15→09:19:39), and the matrix cell's 3-minute timer fired on resume as
"sender (pqReady) never reported" with empty stderr. Every pre-fix local
loop had a family red inside 6 runs; this is the first loop with none. Ten
runs bound a rate, not a kind. ⛔ **These three figures are the ONLY rates to
quote for this row. Every other one written on this page came from a
partial view and is superseded** — the page has carried six mutually
incompatible versions, which is why the command exists.

The observed failures — four in the functional pack, plus
[14.34](#1434-an-unexplained-intermittent-in-self_enrollment_retrofit_live_testdart)'s,
very probably the same thing — are all waits on update/notify/sync convergence:
`atclient_sync_callback_test` (local pack 2026-08-20: "latest commit entry is
updated when same key is updated and deleted", expected `-` got `*`),
`atclient_sync_conflict_test`, `sync_multiple_client_test`, and
`pq_rollout_matrix_test`'s UC-G1.15. ⚠️ Not a Dart-channel defect — beta is
redder because its timing widens the window, and one commit ran UC-G1.15 green
on stable and red on beta
**Reproduces locally**: `cd tests/at_functional_test && ./runLocal.sh`.

⛔ **Disproven hypotheses are listed and must not be re-walked** — they are listed in
[14.41](#1441-what-the-first-ci-runs-on-the-spike-branch-found), and the two
most attractive are that the progress events are dropped by attaching a
listener late (they are not: the controller is single-subscription and buffers)
and that `syncData()` completing on a failed sync is what fires (it is not:
`SyncStatus.failure` appears zero times in the failing log).

⛔ **Three more disproven, 2026-08-20, so nobody re-walks them.** The expiry hot
loop of [14.45](#1445-an-expired-key-the-client-cannot-delete-pins-it-in-a-hot-loop)
is **not** the cause — the run carrying all three of its loops was green at
177/177, so presence does not produce the failures (a *rate* effect is not
excluded and would need the pack run N times either side of that fix).
`SyncServiceWaitUntilCaughtUp.waitUntilCaughtUp` does **not** guard the null-id
"server and local are in sync" event that `FunctionalTestSyncService` completes
on — `sync_service.dart:90-95` deliberately completes on it too, so the two
waiters do not differ there. And an awaited `put()` **has** reached the sync
queue by the time it returns: `local_secondary.dart` awaits `_enqueueForSync`
before `_update` returns, so "the writes were not queued yet" is not available
as an explanation.

✅ **Two failing runs captured, 2026-08-20 evening, on different instruments.**
(This paragraph said "still no captured failing run" until that evening.)

- **Local**: 4 packs at `cfd511663` — 3 green, 1 red. The red's full log (at
  the pack's own log level) is `untracked/pq-1443-packs/run_4_20260820_223443.log`,
  **on this machine only** — `untracked/` is gitignored. Failing test:
  `atclient_sync_conflict_test.dart` "notify updating of a key to sharedWith
  atSign - using await", asserting at line 76 that the pulled
  `phone_0.wavi@alice🛠` keyInfo carries `conflictInfo` — it was **null**. The
  surrounding log shows the sync pull completing `SyncStatus.success` and the
  key arriving `remoteToLocal`; what did not happen is the conflict
  computation populating `conflictInfo`.
- **CI beta**: run `32418455392` on the same `cfd511663`,
  `functional_tests (beta)`, `pq_rollout_matrix_test.dart` UC-G1.15, cell
  `pqReady → pqActive`: `AtSigningVerificationException` — the envelope's
  rsa2048 signature does not verify against **the one rsa2048 key the
  published `_apsk` advertises**. Fetch with
  `gh run view 32418455392 --log-failed`. The smell is a stale or overwritten
  advertisement: whether the verifier read the signer's `_apsk` or a
  later-published one is a race on record convergence between the matrix's
  stage clients.

Two different failure signatures in one family — do not assume one cause
covers both.

**Shape B is diagnosed at the family level, 2026-08-20, by a three-reader
sweep over the CI log and the source.** The failing verification read
`public:_apsk.primary.a.__e@alice🛠` and found one rsa2048 key that appears
**exactly once in the whole 51,589-line job log — in the failure message
itself** — and is NOT the demo PKAM key (which appears 31 times), so the
advertised candidate was a **fresh matrix-minted signing key** and the
"verifier saw the auth key" scenario is excluded. The mechanism family:
all four matrix stages sign under enrollment `primary`, so every current-arm
client publishes the **same** server record; the publish is
**replace-wholesale** from the client's own keyfile ("anything it leaves out
is withdrawn" — its own dartdoc); the mint decision reads only the local
keyfile; and the only serialisation is in-process per-instance. The
cross-client overwrite plurality is **documented, deliberately accepted
product behaviour** (`signing_key_minting.dart` records three guards built
and abandoned), so the defect is the TEST's construction: four "different
apps" sharing one identity. **Ruled by gkc: each matrix row and column gets
its own enrollment** — which is also the recorded deployment model, app =
enrollment = unit. The exact interleaving that fired is unrecoverable from
this artifact: the matrix children's logs are discarded on success.

**The rebuild landed 2026-08-21, and the full matrix is green at +18.**
What shipped, against the spec as refined by reading the code (two of the
spec's four items were already true — the driver awaits sender exit, and the
child's `exit(0)` means nothing lingers across cells):

- **Per-stage enrollments**, one per stage per role: legacy gets a
  legacy-mode (RSA APKAM) enrollment and the pq stages get pq-mode (ML-DSA)
  ones — the same split the postures' own `authenticationKeyAlgorithm`
  draws, so each stage's envelope-signing fallback is the algorithm the
  stage means. Run-unique `(appName, deviceName)`; the approver relays the
  wrapped symmetric key for legacy and registers its own key package first
  (a pq approval refuses without one). `published` stays unenrolled — it has
  no keyfile parameter and never writes an `_apsk`, so it cannot contend.
- **Minting happens once, driver-side, at enrolment time** — cells copy a
  keyfile that already holds the stage's signing key, so no cell ever
  re-mints and the advertisement is one stable value per stage for the whole
  file. Per-cell minting was tried first and failed UC-G1.14, which taught a
  real product fact: **a re-mint on an enrollment leaves the bare form
  permanently** — retired keys stay advertised, so the record becomes the
  JSON array after the first re-mint, and a deployed reader can no longer
  parse it. Stated for rollout: *pqReady is invisible to a deployed peer
  until its enrollment rotates or re-mints its signing key; after that it is
  fail-closed visible.* Ruled by gkc 2026-08-21: the catalogue says it —
  UC-G1.14 is qualified in place.
- **The child awaits the mint settled before signing** (bounded, loud) — a
  guard now that cells start pre-minted, and the harness-side twin of the
  race [14.48](#1448-a-primary-client-can-sign-with-a-key-its-own-advertisement-just-withdrew)
  recorded — closed product-side by ruling 114 (the sign path awaits
  the mint), which made this guard redundant-but-harmless. ⛔ **Ruling 114 is
  SUPERSEDED by 126 (2026-08-30): the sign path no longer awaits anything, and
  the barrier is deleted.** The harness-side guard is now the only thing of that
  shape left, and it is still harmless.
- The receiver is handed the sender's enrollment id — an `_apsk` address is
  `(atSign, enrollment)`, and a reader handed only the atSign would read a
  record an enrolled sender never writes.

The dump-on-failure the diagnosis called for landed 2026-08-21
(`fce13ca52`): a FAILED cell's error carries the child's `during` and
`stack` fields, and its stderr is dumped after the pipe drains — the child
writes FAILED to stdout before its stack reaches stderr, so an undrained
dump is usually empty. Parked, recorded here so it is not re-derived: a
driver-side `expect` failure on a protocol-green cell still dumps nothing
(the noise lists are `runCell` locals, discarded on return).

**Shape C — the lost delete — diagnosed and fixed 2026-08-21, from a red
the post-rebuild soak captured.** `atclient_sync_callback_test` ("latest
commit entry is updated when same key is updated and deleted", expected `-`
got `*`) — one of this section's ORIGINAL four observations. The red log
(`untracked/pq-1443-packs/run_3_20260821_010609.log`, this machine only)
shows firstkey pushed as `updateAll`, **no delete ever pushed**, and the
pending count at 0 afterwards. The mechanism, confirmed in code: the sync
queue keeps ONE entry per atKey and a second enqueue replaces it, while the
push round's success path removed the entry **by key** — so a `delete()`
landing between the round reading the entry and the server acking the push
replaced the entry and was then discarded with nothing left to retry it.
The same window loses a newer VALUE, invisibly. An awaited `delete()` that
silently never syncs is data loss, not a flake. Fixed: queue entries carry
a monotonic `seq`, the round removes only the exact version it pushed
(`AtSyncQueue.removeIfUnchanged`), and a superseded entry pushes next
round; the keystore-miss drop got the same version check (a delete needs no
keystore value, so it must survive that drop too). Pinned three ways: queue-
level race tests, a service-level differential whose batch stub performs the
racing delete itself and then asserts the second batch carries `delete:` on
the wire, and a mutation run — reverting to unconditional removal reddens
the differential with the defect's own message.

**`sync_multiple_client_test`'s one examined red carries shape C's own
signature, 2026-08-21.** This paragraph said "plausible and NOT established"
until the CI log was actually fetched (`gh api .../jobs/96404479619/logs` —
`gh run view --log-failed` returns a TRUNCATED log for this job and greps as
a false absence). The 16b00787c beta red's failure is
`Value divergence for country_4-987522804: client1=null client2=3242750-…`,
and the log shows, on that exact key, `updateAll` pushed → `delete` queued →
`updateAll` re-queued → **`keystore miss … dropping queue entry`** (the
pre-fix unconditional drop) at 11:22:20.557 — 1.5s before the assertion —
with the healing pulls landing only after it. No `AtTimeoutException`, no
"Have synced 5 times": the channels that would refute shape C are absent.
Also settled: the day's beta runs held exactly ONE sync_multiple red, so the
"1 in 3" and "3 of 5" rate rows counted the SAME instance in overlapping
windows; the other two beta functional reds that day were both UC-G1.15
(shape B), and the one stable functional red (run 32382811883) was
`atclient_sync_conflict_test`'s conflictInfo case — shape A's test. One
classified instance is not proof every past red was shape C, but no
unattributed sync_multiple observation remains. Mechanism context, measured
from local pack logs: this test is the pack's only manufacturer of the shape
C window — every post-fix "re-enqueued mid-push" save and every
"keystore miss" drop in any pack log falls inside its window, on its own
keys — and a plain ack-path loss self-heals here (the pull re-applies the
acked server value; `isInSync` is cursor-based), so only the narrower
orderings redden it. Discriminators for any FUTURE red of this test, which
at or after `e76b0038b` would be evidence of something shape C's fix does
NOT cover: SEVERE `Value divergence` with one side null and no
`Will push SyncQueueOp.delete` for that key afterwards points back at a
queue drop (check for a `re-enqueued mid-push` line for the key); a red
presenting as a timeout or "Have synced 5 times" was never shape C's
signature at all.

**Shape A is diagnosed, from the red log's own lines — a measurement, not a
hypothesis.** `SyncServiceImpl.stop()` halts future triggers and cannot halt an
in-flight run: `processSyncRequests` checks `isStopped` only at entry
(`sync_service_impl.dart:272`) and never after resuming from an await, and its
first await — `_isInSync()` → `_getServerCommitId(forceFresh: true)` — is a
network round-trip. In the red run the harness's own `syncData` request entered
processing and parked on that await; the test's `stop()` returned at
`22:37:03.077489` ("Stopping sync service"); the test staged its five puts; and
at `22:37:03.086665` the parked run resumed, read `pending push count: 5`, and
ran a full `syncInternal` — five "Will push" lines follow — destroying the
staged conflict before the measured sync ran. The three green logs show the
same slice with the prior run fully finished before `stop()`, so no rogue run.
The `start()` dartdoc documents the in-flight run surviving `stop()` "to set
flags back on its own" — the survival is designed, but the survivor does
*work*, not just unwinding. Same shape as the Monitor start/stop race this
package already fixed with a done-completer.

**Fixed, same day.** `processSyncRequests` re-checks `isStopped` after its
opening await and answers the request "SyncService has been stopped";
`_throwIfStopped()` guards each stage boundary and each push/pull round in
`syncInternal`; and `stop()` awaits the in-flight run's unwinding via a
done-completer, so "halts sync activity" is true when `await stop()` returns.
Pinned by `test/sync_stop_race_test.dart` — a parkable stats fetch reproduces
the exact park-resume shape; reverting either half of the fix reddens the
tests with the right messages (run, not reasoned), and a control arm proves
the parked run does work when *not* stopped, so the verifyNever cannot pass
vacuously. A unit test for mid-sync `stop()` existed once and was retired
(`sync_service_test.dart`'s own header records it) on the claim that
`atclient_sync_conflict_test` covered it end-to-end — the covering test is the
one that flaked, which is what "a test is the specification of the mechanism
it guards" is about. Evidence at the fix commit: unit 1484/1484; one
functional pack 177/177 with the rewritten harness taking 4 extra
truth-checked sync rounds that the old harness would have skipped.
**Post-fix packs at `7f24542eb`: 6 runs — 5 green, 1 red**, and the red is
NOT shape A's test (`atclient_sync_conflict_test` was green in all 6) nor any
previously recorded family member — it is the new member below. Six packs
without a shape-A recurrence bound a rate, not a kind; the mutation-proven
unit tests are what carry the fix's proof.

**A sixth family member, captured 2026-08-20 in post-fix run 6**
(`untracked/pq-1443-packs/run_6_20260820_235557.log`, this machine only):
`nskey_rotation_live_test.dart` UC-A5.1(b) — the survivor's read of the
rotated `__nskey` advertisement returned kid `e05da79630eb0db1` where the
successor `ceccdd0bb19ba1ad` was expected, and the log's own rotation line
names `e05da796…` as **the pre-rotation generation**, so the read served the
superseded advertisement. The assertion reads
`PublishedNskeyKeyRing.currentPublic` — while the test's own comment above
it claims "the atServer's own copy" — and `currentPublic` never promises
that: it serves this ring's `_ownCurrent` and `_remote` caches inside a
15-minute `advertisementTtl`, and then a **LOCAL-first** get. **The recorded
hypothesis here — that the survivor fetched generation 1 earlier inside the
ttl and the cache served stale — is contradicted by the source, 2026-08-21:**
`survivor.ring` is a fresh per-test instance whose first-ever use IS the
assertion, so both per-instance caches were empty; the ttl is irrelevant to
a first read. What fired is the fetch arm itself: for an own-atSign public
key the get routes to a local llookup of the one Hive box every same-atSign
client in the process shares, and the red log shows sync-pull writes of
`public:__nskey.buzz` landing between the rotation's local generation-2 put
and the failing read — an in-flight pull regressed the shared box to
generation 1 while the atServer already held generation 2. The fix is still
the TEST's (the product's caching and local-first sender read are deliberate
and documented), but "a fresh ring" would NOT fix it — a fresh ring's
`currentPublic` still reads local-first and inherits exactly the staleness
that fired. The one genuinely cache-skipping read is
`publishedAdvertisement` (remote-only, signature-verified — what the mint
path uses for the same reason). Three sibling assertions share the shape:
the same file's UC-A5.3 read (self-confirming — it answers from the cache
the rotation itself just wrote), `nskey_published_ring_test.dart`'s
post-rotate fresh-ring read, and `pq_signing_root_mint_lock_test.dart`'s.
Discriminator for a second red: NOT "find the survivor's generation-1 fetch
earlier in the log" (its local read logs nothing, and there was no earlier
fetch) — look for `Pulling to local: UPDATE: public:__nskey.<ns>` between
the rotation's publish and the assertion. Side observation for a product
ruling: the regression this rides on is the sync pull applying an OLDER
server entry over NEWER local state — the pull-side face of this family,
which shape C's push-side versioning does not cover. The test-side fix
landed 2026-08-21 (`ccf4987a4`): all four exposed assertions read through
`publishedAdvertisement`, and one functional pack ran 177/177 with them.

⚠️ **"The fix is still the TEST's" was wrong, and the same assertion proved it
2026-08-25.** UC-A5.1(b) went red again — twice in seven runs of one commit —
now reading through `publishedAdvertisement`, which is remote-only. So the
stale generation was not the shared Hive box: the **atServer's own copy had
regressed**. The atServer log attributes it exactly, both connections belonging
to the same enrollment: the rotation's `update` carried the successor at
21:08:20.8668, the same client's sync pushed a `batch` carrying the predecessor
at 21:08:20.8808 — byte-identical to the batch it had sent six seconds earlier,
same `dataSignature`, same `createdAt` — and the survivor's `llookup` at
21:08:20.8984 was served the predecessor, which then stood for the remaining
100 seconds of the run. In all five green runs of the same pack that second
batch carried the successor, so it is a race rather than a switch. This is the
push-side face that this entry's own "side observation for a product ruling"
predicted, at the same key. `_mint`'s local write was what queued it: a
sync-queue entry is `{atKey, op, ts, seq}` with **no value**, so a drain sends
whatever local storage holds when it runs. Fixed by removing that write.
`currentPublic` now reads local first and falls back to the atServer, so the
record the minter no longer writes is still answered for in the window before
sync pulls it down, filing what it fetched with `cameFromServer: true` — the
flag the sync-queue enqueue refuses on, so the cache write cannot become a
push.

**Measured after the fix, same image (`at_virtual_env:g0fixed`), same machine:
25 rotations, 0 red.** Five full-pack runs at 183/183 (2 skipped), and 20
iterations of `nskey_rotation_live_test.dart` alone. ⚠️ **The targeted
iterations are the weaker half** — the file runs by itself, so the atServer is
under far less load than in the runs that went red, and a race probe that comes
back clean is a claim about the load it ran at. The stronger evidence is
structural: the atServer's own log shows **0** `RCVD: batch` pushes of
`public:__nskey.buzz@bob🛠` in all 25, against 2 in every run before the fix,
red or green. Positive control in every one of the 25: both `update` verbs
decode, so the zero is an absence rather than a decode that found nothing.

Re-derive rather than quoting: run the pack with
`VIRTUALENV_IMAGE=at_virtual_env:g0fixed`, capture `/apps/logs` from the
container, and decode every advertisement write with a script that base64-opens
each `payload` and prints the `kid` — a `RCVD: batch` line for that key is the
clobbering push. ⚠️ The rotation test cannot be looped inside one virtualenv:
its enrollments are run-unique but its namespace is a fixed `buzz`, so a second
iteration finds the advertisement already published, `mintAndPublish` adopts
instead of minting, and the private this process never minted is absent.

**The harness half, also visible in the red log:**
`FunctionalTestSyncService.syncData` completed 610µs after starting — too fast
for its own enqueue → network → verdict — so it completed on the **previous
run's** progress event and stranded its own request, which is the one that went
rogue. That widened the already-recorded harness defect below (completing on
`SyncStatus.failure`): it completed on the first success-or-failure event
regardless of *whose* event it was. **Both halves fixed with the product fix**:
`syncData` now consumes events with `await for` and completes only when the
service's own `isInSync()` answers true — an event is treated as "a run
finished", never as "this call's work is done" — and a failure event means
retry (bounded), never done. Whether shape B (UC-G1.15) reduces to any of this
is **not established**.

⚠️ **Start by reading [14.34](#1434-an-unexplained-intermittent-in-self_enrollment_retrofit_live_testdart),
which is very probably the same thing.** It records an unexplained intermittent
in the same pack, timing out at `await firstNotification`, passing when its file
runs alone — recorded 2026-08-17 and recurring 2026-08-19, well before the four
below. That makes **five** files in one family, not four. ⚠️ Do NOT pool the
rates: 14.34's observations (1 of 5 runs, then 1 of 2) were taken on tree states
this branch has since moved past — 14.34 says so itself — and on a different
file. Two figures from different instruments are not a comparison, however
carefully each was taken. **Not asserted as identical**; nobody has shown one
cause covers both.

⭐ **The pattern to look for first: a test that passes only because of what
ran before it.** Three independent instances on this branch now, two of them
found by different people:

1. **UC-A4.2's control** asked whether @bob was ready for the shared namespace
   while nothing in its own file made him ready — green only when one of three
   other files had minted first. Fixed `454bedbbd`.
2. **`encryption_test.dart`'s monitor replay** — fixed on trunk by
   `6b91035b4` and arriving here with the 2026-08-20 merge. Its commit message
   is the clearest statement of the shape: "*without it this test only passes
   when some other test file happened to start atSign_2's monitor first, which
   is what made it flake*".
3. The four convergence failures above — **unproven**, but this is where to
   look before anything subtler.

⚠️ Instance 2 rests on **deliberate** product behaviour, not a defect, and the
distinction matters: `NotificationServiceImpl.getLastNotificationTime()`
returns null on its FIRST call for a keystore and seeds the record — confirmed
at `notification_service_impl.dart:439-444`, "*return null for THIS call to
keep first-run semantics ('don't replay history I never saw')*" — and a monitor
started with null asks the atServer for no replay. So a first-run subscriber
correctly misses what preceded it, and a test wanting replay must burn that
call itself. Do not "fix" the product here.

**A separate defect found in the same place — now fixed with shape A's fix.**
`FunctionalTestSyncService.syncData()` used to call `syncOutcome.complete()` on
`SyncStatus.failure`, so a **failed** sync returned to its caller as success.
The rewrite retries on failure (bounded at five rounds) and throws if still
not in sync.

### 14.45 An expired key the client cannot delete pins it in a hot loop

⛔ **Pre-existing on `origin/trunk`, not introduced by this branch** —
`_armExpiryTimer` has 5 hits and `deleteExpiredKeys` 2 there. Found 2026-08-20
while running the pack for [14.43](#1443-the-functional-suites-convergence-race).

**The loop, read from source.** `AtClientImpl._armExpiryTimer`
(`at_client_impl.dart:769`) arms `Timer(Duration.zero, _onExpiryFire)` whenever
the earliest expiry is already in the past — its own dartdoc says so.
`_onExpiryFire` runs `LocalSecondary.deleteExpiredKeys`, whose per-key `catch`
(`local_secondary.dart:585`) logs the failure at `warning` and moves on **without
removing the key**. `_onExpiryFire`'s `finally` then re-arms. The earliest expiry
is still in the past, so the timer is `Duration.zero` again. Nothing removes the
key, nothing backs off, nothing gives up: the client spins for the remainder of
its own lifetime, one `warning` line per turn of the event loop.

**Measured, one local pack run — THREE keys, three loops, all `_nskeylock`:**

| Key | Iterations |
|---------------------------------------------------|-----------:|
| `_nskeylock.cooldown1787252300302993.buzz@bob🛠`   | 186,994 |
| `_nskeylock.ns1787252329248768.wavi@alice🛠`       | 19,965 |
| `_nskeylock.rot1787252358178828.wavi@alice🛠`      | 18,762 |

225,721 in total, **47.4% of the run's 394,523 log lines**. Each is refused with
`Cannot perform delete … due to insufficient privilege`. Intervals tighten from
1259 µs to about 120 µs. The first began during `nskey_rotation_live_test.dart`
and ended only when that test file ended and the next one loaded — *not* by
resolving.

**This is designed-in, not incidental.** `MintLock` releases by ttl and by
nothing else — `mint_lock.dart:80`, "**The winner does not release the lock; the
ttl does**" — so every mint and every rotation creates a record whose only exit
is expiry, and the client cannot delete it when it expires. Every lock is
therefore a future hot loop, and the three above are one run's worth of
ordinary minting.

**Where it comes from, read in the dependency.** `nextExpiresAt()` reports the
earliest expiry in the store **including ones already past**, on both backends
of at_persistence_secondary_server 5.2.1 — Hive takes a bare minimum over every
record with an `expiresAt`, SQLite runs
`SELECT MIN(expires_at) … WHERE expires_at IS NOT NULL`. Its sibling
`nextAvailableAt()` filters (`available_at > ?`; Hive comments *"Strictly after
the cutoff: already-born keys are excluded"*). The asymmetry is fine on its own
— a past expiry means "sweep now" — and at_client's `_armExpiryTimer` is what
adds the assumption that the sweep will then clear it.

✅ **FIXED — the spin, not the refusal.** `AtClientImpl._onExpiryFire` now reads
`deleteExpiredKeys`'s return count and passes `afterFruitlessSweep: removed == 0`
to `_armExpiryTimer`, which floors the delay at 30s instead of arming zero when
the expiry is past and the sweep achieved nothing. The retry survives, so a
refusal that turns out to be transient still heals and a later expiry is still
collected. `AtClientImpl.expiryTimerDelay` is `@visibleForTesting` and its four
branches are pinned in `test/at_client_expiry_timer_test.dart`; reverting the
fix reddens the backoff test, quoting its own reason. ⚠️ **What that test does
NOT cover** is the single line feeding it — a change that always passed `false`
would leave the suite green and restore the spin. Observing it needs a built
`AtClientImpl` with an injected `LocalSecondary`, which was judged not worth the
scaffolding; the test file says so at the top.

✅ **The refusal is FIXED too, and it was not about immutability.** Traced
2026-08-20: the sweep's delete is refused by `isEnrollmentAuthorizedForOperation`
in `LocalSecondary._delete` — a **namespace** check — before any keystore or
server interaction. The lock key parses as `KeyType.selfKey` with namespace
`buzz`/`wavi`, so it is not in the skip list (`reservedKey`, `cachedSharedKey`,
`cachedPublicKey`, `localKey`). The sweep passes `localOnly: true` and so never
builds a `delete:` command at all, which is the only place `force:` appears —
and the client keystore has no immutability guard on remove (`immutable` occurs
20 times in at_persistence_secondary_server 5.1.0, in metadata serialization and
in `AtMetadataBuilder` preserving it across *updates*, never in a remove path;
control: `expiresAt` occurs 68 times). Immutability is the atServer's
enforcement, on the `delete` verb.

`deleteExpiredKeys` now passes `isExpiry: true`, which skips that check.
Reclaiming an expired record is storage internals, not an operation an
enrollment performs, and the scoping is unaffected because an expiry deletion is
local-only and never enqueued for sync. `test/expiry_sweep_authorization_test.dart`
pins both arms — an enrollment-initiated delete outside its namespace is still
refused, and the sweep reclaims the same record — and reverting the bypass
reddens it.

⛔ **Parked by gkc 2026-08-20: why the lock is in local storage at all.** It is
created remote-only (`MintLock._take` → `getRemoteSecondary().executeVerb`, and
`_isOwnLock` → `getRemoteSecondary().executeCommand`), and arrives locally by
the sync pull — the never-synced rule covers `public:_`, not self keys, and
`syncRegex` defaults to null so the pull is unfiltered. Two things stop a client
suppressing it today: the client API has no working suppression control —
`RemoteSecondary.executeVerb`'s `sync` parameter was inert and is now
`@Deprecated` (14.46; `_take` no longer passes it) —
and `:nc`/`noCommit` — which would stop the atServer logging the commit — exists
in at_commons (published 5.15.0, syntax groups for `update`, `update:meta` and
`delete`) but appears in **zero** files of at_server `origin/trunk`.

⚠️ **Owed against `at_persistence_secondary_server` (5.1.0), not fixable here.**
`HiveAtKeyValueStore.get()` does not filter expired records, and carries three
comment lines describing the filter that was never written — *"load metadata for
hive_key / compare availableAt with time.now() / return only between ttl and
ttb"*. It throws `KeyNotFoundException` only when the value is **absent**. So
expiry filtering lives in one caller: of **14** direct `keyStore.get`/`getMeta`
reads in at_client's `lib`, only `LocalSecondary._llookup` applies
`_isActiveKey`. Most of the rest are benign — the private-key getters have no
ttl, and `prevMeta` wants the pre-write value deliberately — but the filter
belongs in the store. ⛔ Do **not** "fix" `_llookup` to throw for an expired key:
returning `'data:null'` is the documented contract, stated at
`collections.dart:1366` as *"data:null (availableAt in future, or post-expiry)"*
and tested for at 16 call sites across 5 files.

⛔ **It is NOT what fires [14.43](#1443-the-functional-suites-convergence-race),
and this is a measurement rather than a guess.** The run these figures come from
was **fully green — 177/177, exit 0** — with all three loops running in it. So
the loop's *presence* does not produce the convergence failures, and a future
session should not adopt it as the cause on the strength of how alarming it
looks. What one green run cannot exclude is a *rate* effect: more event-loop
saturation widening an existing window. Settling that needs the pack's failure
rate over N runs with and without a fix, which is expensive and should wait
until the loop is fixed anyway.

### 14.48 A `primary` client can sign with a key its own advertisement just withdrew

Found 2026-08-20 while diagnosing [14.43](#1443-the-functional-suites-convergence-race)'s
shape B; filed by gkc's ruling as a product row, distinct from the accepted
overwrite plurality. That acceptance
(`signing_key_minting.dart` — "three guards were built and all three broke the
live enrollment path") is about two **clients** overwriting each other's
`public:_apsk.primary.a.__e` record in turn. This row is about **one** client
racing itself:

- `PqClientBootstrap.startup()` is fire-and-forget
  (`at_client_impl.dart:677-698` region), so minting runs concurrently with
  whatever the app does next;
- `SigningKeyMinting` **publishes before filing** — the advertisement carries
  the fresh key before the keyfile does;
- `ApkamSigning.signingKeys` reads the keyfile per call and **falls back to
  the APKAM authentication keypair when it holds nothing**
  (`apkam_signing.dart:171-195`);
- the composition **withdraws** the authentication key on the first mint:
  `apskEntries` (`apsk_composition.dart`) adds the auth key only while the
  enrollment holds no signing key of its own — the same condition the
  signing fallback keys on, by design, "so what signs and what is advertised
  cannot disagree".

Interleave those and a client signs an envelope with the auth fallback in the
window where its own advertisement already names only the minted key — an
envelope nothing can verify, thrown by the verifier as "does not verify
against any of the 1 rsa2048 key(s) the published `_apsk` advertises". The
mirror-image window (sign first, publish lands before a peer's fetch) fails
the same way. Per-stage enrollments in the matrix test do not close this —
it is one process, not two.

**The prerequisite check is answered, 2026-08-21, and it narrows nothing:
ENROLLED clients share the window.** This section used to say the withdrawal
came from "the bare advertisement form holds exactly one key" and to ask
"whether the JSON form's `authentication` entry already rescues enrolled
clients". Checked at the source: no such entry exists — the wire form
(`apsk_advertisement.dart`) emits only `v` and `keys`, `enroll:update` sends
the entries verbatim, and the withdrawal lives in the shared composer, so
the JSON/array form withdraws the auth key identically. (The bare form's
single slot is a second, independent constraint on fix 3 below, not the
withdrawal mechanism.) Two stale dartdocs — `apsk_advertisement.dart` and
`envelope_signature.dart` — still describe auth-key *retention* that commit
`4c4279be4` deliberately removed; they want correcting whichever way the
decision goes.

**Ruled by gkc, 2026-08-21: candidate 1 — the sign path awaits the mint.
Built the same day; the mechanism and evidence are decisions.md 114.**
⛔ **SUPERSEDED by 126 (2026-08-30) — the barrier is deleted.** Candidate 3
(retained auth-key entry) stays rejected for the reason given below; what
changed is that no mint withdraws the authentication keypair at all, so
neither candidate is needed. The reasoning is in decisions.md 126.
`signingKeys` waits on a per-client barrier the bootstrap settles at its
mint step (and on stop, failure and gated-off); the mint itself is the one
exempt signer. Differential and mutation runs green, unit 1495/1495, one
functional pack 177/177 with the barrier live. The other two candidates
stay recorded below with the trade-offs that argued them down:

1. **Sign awaits mint.** A mint-settled completer on `PqClientBootstrap`
   (settled in a `finally` so gated-off/failed paths release it), awaited in
   the sign path. Closes both windows for every in-process signer; costs an
   early sign one round trip. It must NOT await `startupComplete` — the
   bootstrap's own later steps sign, so that deadlocks. Real design cost:
   `ApkamSigning` holds only the `AtClient` spec, which does not expose the
   bootstrap — a spec addition breaks every `Mock implements AtClient` at
   runtime, so it is a downcast or constructor injection.
2. **`wrapAndSign` refuses until minting settles.** Same plumbing, throw
   instead of await. No deadlock risk, no silent delay — but the race becomes
   visible refusals, including for envelope-listener responses (the listener
   starts one bootstrap step before minting), and every refused response
   needs a retry story or it is a silent drop.
3. **Composition keeps the auth key as a retired entry.** ~5 lines in
   `apskEntries`, and the verifier already accepts it (retired entries are
   kept and every candidate key is tried). Uniquely, it also rescues durable
   envelopes signed with the auth fallback BEFORE the first mint — a superset
   of the race, and the composer's own doc names revisiting exactly that
   premise. But at the bare stage two entries force the JSON array onto a
   record every deployed consumer base64-decodes as a bare RSA key — the
   breakage rollout 1 exists to prevent, and the reason `4c4279be4` removed
   retention. A scoped variant (retain only when the value is the array
   anyway) is deploy-compatible but leaves the bare stage — where the window
   was measured — open, so it can only accompany 1 or 2, not replace them.

Open beneath the choice: whether any deployment already holds durable
auth-fallback-signed envelopes from before a first mint (if so, the first
mint unverifies them all regardless of the race, and only 3 helps); and the
verifier's pubKeyCache asymmetry — a peer holding the pre-mint advertisement
verifies window-signed envelopes for up to the cache expiry while a
fresh-fetching peer refuses them.

### 14.49 `KeyEntryStatus` becomes a typed String, and the release train is all candidates

**Two rulings by gkc, 2026-08-22.** Recorded together because both are cheap
only while these packages are unpublished.

#### 14.49.1 `KeyEntryStatus` becomes a typed String wrapper — DONE 2026-08-22

Ruled and built the same day. `KeyEntryStatus` now has the shape
`CryptographicMaterialStatus` already had: a class of `static const String` constants, an open
value, and an unknown token **preserved** rather than flattened. What landed is
at the bottom of this section; the ruling and its evidence are kept because they
are what the shape has to go on being right about.

⚠️ **The `CryptographicMaterialStatus` justification does NOT transfer, and stating it
wrongly would send the next reader looking for a bug that is not there.**
That conversion was forced because the old reader *threw*: an unknown status
refused the whole keyfile, so any new value was a permanent at-rest break.
`KeyEntryStatus.fromWire` already tolerates unknowns without throwing
(`key_entry_status.dart`: absent or `active` → active, **anything else →
retired**). Its problem is not refusal but **lossy** tolerance.

What is actually wrong, measured 2026-08-22:

- **The open type feeds the closed one and the openness is discarded one hop
  later.** `key_package_persistence.dart:86` maps
  `material.status == CryptographicMaterialStatus.active ? KeyEntryStatus.active :
  KeyEntryStatus.retired`. `CryptographicMaterialStatus` was made open precisely so an
  unrecognised value round-trips unmodified; that value is collapsed to
  `retired` at this seam.
- **A round trip rewrites a newer client's stronger statement.** The reader
  collapses any unknown to `retired` (`apsk_advertisement.dart:145`) and the
  writer emits `key.status.name` (`:59`), so a `revoked` read by this build
  and written back becomes `retired`. ⚠️ **This bullet overstated the `_apsk`
  case and was corrected while building, 2026-08-22.** No caller reads an
  `_apsk` record and republishes its entries: every `_apsk` writer composes
  from local key material (`apskEntries` from the keyfile, or a single freshly
  minted key at `pq_signing_root.dart:497`). So for `_apsk` the loss is a
  property of the reader/writer pair, not a live path — pinned as a format
  rail, not sold as coverage. The **live** version of the same loss is the
  seam in the bullet above, keyfile → record, and it is why that seam is the
  one that matters.
- **The collapse is fail-OPEN in the direction that matters.** Retirement
  withdraws the future and preserves the past — a retired signing key still
  verifies what it signed. A compromised key must not. Mapping an unknown
  `revoked` to `retired` therefore leaves an older build verifying forgeries.

Extensions to expect, in rough order of likelihood: **`revoked`/`compromised`**
(must restrict verification, which the binary cannot express), **`suspended`**
(temporary, where `retired` is a one-way door), **`pending`/`provisional`**
(advertised ahead of activation, never becoming usable for a build that
predates the value).

The shape wanted: keep the raw token; offer `bool get offeredForNewOperations`
for the sign/seal decision and something honest for the verify decision, so an
unknown status can be treated as **more** restrictive rather than silently as
`retired`.

⛔ **`EnrollmentKeyExchangeMode` stays an enum. Do not convert it.** It is
never parsed from any wire or JSON value — every use site sets it locally (two
named constructors fix it, `enrollment_submitter.dart` branches on it,
at_client re-exports it for `PqPosture`). Nothing outside this process writes
it, so there is no forward-compatibility problem; a third mode later is
additive and the only thing it breaks is an exhaustive `switch` the compiler
will point at. An open String would trade a checked domain for stringly-typed
branching and buy nothing. Revisit only if an atServer or a peer starts
reporting it back.

Scope: **132** references across the tree at `8b08174b5`, not the 107 this said
when it was written and not the 126 measured mid-change — the tests added here
moved it. Re-derive rather than quoting:
`git grep -c KeyEntryStatus | awk -F: '{s+=$2} END {print s}'`. Pinned by
raw-literal wire tests in **both** packages' `wire_literal_pins_test.dart`.

**What landed.** `key_entry_status.dart` is a `class` of `static const String`
constants with `known`, and three functions:

- `fromWire(Object?)` — absent is `active`, anything else is the token itself.
  A non-String is stringified rather than repaired, which keeps it out of both
  known values and keeps what was written visible in a log.
- `offersNewOperations(String)` — the sign/seal question. Only `active`.
- `vouchesForPastOperations(String)` — the verify question. `active` and
  `retired`, spelled out rather than as `known.contains`, because a token joins
  `known` by being *understood* and the first one anyone adds is likely to be
  one that must fail this.

`ApskSigningKey` carries both as getters, `PackageKey`, `PersistedEncKey` and
the mixin's held key carry the first. **Both** collapsing seams were fixed, not
the one this section named: `key_package_persistence.dart` (adoption at
startup) and `key_package_minting.dart`'s `advertisedKeysIn` (the republish),
which each mapped the keyfile's own open `CryptographicMaterialStatus` onto one of two values.

**The verify half is wired, not merely offered.** Two call sites drop an entry
whose status they cannot read: `parseApskValue`, so `verifyEnvelope` refuses an
advertisement of nothing verifiable rather than half-reading it, and
`PqSigningChain._rootCandidates`. Filtering there rather than inside
`apskSigningKeys` is deliberate — that reader also feeds the *writers*, which
have to republish a token they do not understand rather than delete it.

**The third record followed, ruled by gkc the same day.** `_apsk` had the same
seam in a worse form: `AtKeys.retiredSigningKeysFor` selected on *exactly*
`CryptographicMaterialStatus.retired`, so a signing key carrying a token this build had never
seen was in neither list and was **dropped from the advertisement entirely** —
and because `_apsk` is rewritten whole on every publish, an omitted entry is a
withdrawal. It erased the key that verifies what it signed along with whatever
its owner last said about it.

⚠️ **That skip was a written, reasoned decision, not an oversight** — its
dartdoc said advertising such a key "would state something about it this build
does not know". True while the advertisement could only say `active` or
`retired`; the open token is precisely what removes the premise, because the
entry can now carry the keyfile's own word. The method is
`withdrawnSigningKeysFor`, selects on not-active-and-not-`dead`, and returns the
token; `apskEntries`' `retired` parameter became `withdrawn` and writes it
through. Keys a call is withdrawing *right now* are still stated as `retired` —
that is the caller's own act, not a value it read. Free to do only because the
whole signing-key family is unpublished: it appears in zero files of at_auth
3.3.0.

Eleven tests, each mutation-proven by reverting its own fix and reading the
failure message: the two seams, the two verify sites, an `_apsk` round trip
that shows a `revoked` token read and written back unchanged, the predicate
table, a `PackageKey` round trip, the widened `_apsk` selector with `dead` as
its control, the composer's write-through, and the deliberate asymmetry between
the two readers — at_auth's keeps an unreadable entry because the writers
republish what it returns, at_client's verifier drops it. `at_auth` 335/335, `at_client` 1509/1509, the
functional pack 178/178, workspace analyze clean and the at_client format gate
clean. The `at_client` pin that asserted
`fromWire('verifyOnly') == retired` went red on its own and its rewrite is the
review of the behaviour change.

#### 14.49.2 Every remaining package publishes as a release candidate

Ruled by gkc. at_lookup `3.7.0-rc1` and at_server_status `1.1.2-rc1` are
merged; at_auth `4.0.0-rc1`, at_client `3.15.0-rc1`, at_client_flutter
`1.1.5-rc1` and at_onboarding_cli `1.17.0-rc1` are on the spike awaiting their
carves.

**Why all of them, not just at_lookup:** a package that declares a candidate
floor and publishes as STABLE resolves its consumers onto the candidate anyway,
through a version bump they take without thinking.

**The prerelease rule this rests on, measured rather than assumed:** a caret
range does **not** admit a prerelease of its own lower bound (`^3.7.0` rejects
`3.7.0-rc1`), but **does** admit one strictly above it (`^3.6.0` accepts
`3.7.0-rc1`). That is why at_lookup's and at_auth's bumps forced constraint
changes while the others needed none.

⚠️ **OWED AT THE REAL RELEASE, and recorded here because a commit message is
not a durable home for it:** every constraint moved to a `-rc1` floor reverts
to its stable form when these publish, or a stable release ships requiring a
candidate. The sites: `at_lookup: ^3.7.0-rc1` in at_auth, at_client and
at_server_status; `at_auth: ^4.0.0-rc1` in at_client, at_client_flutter,
at_onboarding_cli, `tests/pq_matrix/current`, both live test packages and
three at_client_flutter examples. Re-derive with
`git grep -n 'rc1' -- 'packages/*/pubspec.yaml' 'tests/*/pubspec.yaml'` -
measured, `*` crosses `/` in a git pathspec so it reaches the nested ones.

**at_auth is a MAJOR, ruled by gkc 2026-08-22** - `4.0.0-rc1`, not
`3.4.0-rc1`, which is what this section said until that ruling. The typed
keyfile's field names change (`keyParts`/`keyPartType`/`keyAlgorithmType`
become `material`/`role`/`algorithm`) and `KeyPartStatus` becomes
`CryptographicMaterialStatus`. The five constraint sites that floored at_auth
at a stable `^3.0.0` - both live test packages and three at_client_flutter
examples - moved to the candidate floor with the rest, so they revert too.
`packages/at_chat_flutter/example` is deliberately left at `^3.0.0`: it has no
path override, so it resolves published at_auth and a candidate floor would
strand it.

**at_client stays a MINOR, ruled by gkc 2026-08-22** - `3.15.0-rc1`, and
at_auth is the only major in this train. Its in-progress section carries
several **BREAKING** labels, which is what keeps prompting the question:
- `PackageKey.status`'s type change is accepted.
- `apskEntries` is **not public API at all**. It is absent from
  `packages/at_client/lib/at_client.dart`, and every importer reaches it
  through `package:at_client/src/signing/apsk_composition.dart`, so no
  consumer can observe its signature. Re-derive with
  `git grep -n apskEntries -- packages/at_client/lib/at_client.dart`, which
  returns nothing against a positive control of `apskEntries` in 4 other
  at_client Dart files (`apkam_signing`, `apsk_composition`,
  `signing_key_minting`, `apsk_formats_test`).
- The four typed vocabularies are `extension type ... implements String`,
  erased at runtime, so nothing published loses a member or changes shape.

The same test the 3.14.1-to-3.15.0 ruling used applies: semver keys on what a
consumer can observe, and nothing published was removed. That earlier ruling is
recorded as an HTML comment at the top of `packages/at_client/CHANGELOG.md`.

#### 14.49.3 Considered while building 14.49.1, and deliberately not done

These are here to **stop** the next reader building them. Each looked like a
defect during the adversarial review and is not one, or is a real question that
was left open on purpose.

- **`KeyEntryStatus.known` is not dead code — do not delete it.** Its only
  consumer is a raw-literal wire pin, which is exactly the arrangement
  `CryptographicMaterialStatus.known`, `CryptographicMaterialAlgorithm.known` and `CryptographicMaterialRole.known`
  already have beside it. The pin is the point: it makes re-spelling the
  vocabulary an edit somebody has to review.
- **`fromWire` stringifying a non-String value is deliberate.** It keeps a
  malformed status out of both known tokens, so both predicates answer no —
  the maximally restrictive reading — and it keeps what was actually written
  visible in a log. `active` would be fail-open, `retired` is the flattening
  this whole item removed, and a sentinel would put a token on the wire that no
  writer ever meant.
- **The empty string is not special-cased.** It is not `active`, so it is
  unknown, so it is maximally restrictive. A fourth behaviour for a value
  nothing writes is a branch nothing exercises.
- **The two serializers compare `status != KeyEntryStatus.active` rather than
  calling `offeredForNewOperations`, and they must not be unified.** A
  serializer asks "do the bytes need this field"; the predicate asks "may this
  key be used". Same answer today, and they diverge the moment a token is added
  that is offered for new operations without being spelled `active`.
- **OPEN, not rejected: a held KEM key whose status this build cannot read
  still opens envelopes addressed to it.** `KeyPackageRegistration.encKeyFor`
  does not consult status, which is right under the retained-key doctrine — a
  holder opens what was already sealed to it — and the unknown-token rule as
  built governs *choosing* a key, never opening one you hold. But an owner
  writing `revoked` may well mean "stop opening too". Not built, because
  refusing would strand envelopes on a guess about a token nobody writes yet.
  Revisit when the first real third token is defined, and decide it there
  rather than here.
- **`PqSigningRoot._signingPrivate`'s `held.length <= 1` short circuit is left
  alone.** It returns a lone private without consulting the record, which
  reads alarmingly next to the new fail-closed filters. Its dartdoc gives the
  reason — four production call sites take it as the cheap local check before a
  round trip, one of them on the approval path — and names
  `reconcileHeldPrivate` as the owner of the heal. That heal now makes the same
  vouching judgement as the verifier, which is what covered the case that made
  this worth looking at.

### 14.17 Signature agility — complete

✅ **COMPLETE 2026-08-18.** Steps 1–5 are done and step 6 is out of scope by
gkc's ruling. The last piece to land was step 5's signed-envelope 3×3
(UC-G1.15), which is what makes
[`decisions.md` 108](decisions.md#108-the-signing-rollout-swaps-algorithms-it-never-overlaps-them-2026-08-18)
a measurement rather than a ruling.

⚠️ **This entry spent five days claiming steps 4 and 5 were owed after they had
shipped**, because it was written 2026-08-11 and never re-read against the tree
while [14.18](../implementation-plan.md#1418-the-remaining-d1-initial-development-sequence) built the
work. The individual strikes below say what each row used to claim. The reason
nothing caught it is worth more than the corrections: the `UC-G1.x` rows this
entry is accepted against are the one cluster of the catalogue no rail checks —
`manifest.dart`'s regexes hard-code `UC-[ABC]`.

The design landed 2026-08-11 as [`decisions.md` 91](decisions.md#91-signature-agility-the-apkam-auth-key-stops-being-the-enrollments-signing-key-2026-08-11),
[`design.md` 9](../design.md#9-subsystem-g--signature-agility-the-authsigning-key-split)
and [`acceptance.md` 16](../acceptance.md#16-g1--signature-agility-and-the-rollout-matrix).
This entry is the owed half; the rulings are the contract.

**Owed, in dependency order.**

1. ~~**Drop at_server's at_commons override.**~~ **DONE 2026-08-11.** The
   override is out of both `pubspec.yaml` and `pubspec_overrides.yaml`,
   `pubspec.lock` resolves at_commons from hosted 5.14.0, the
   `at_commons-apsk-1` tag is deleted local and origin (its commit `54ccffdd0`
   is an ancestor of trunk, so nothing was orphaned), and
   [at_server#2744](https://github.com/atsign-foundation/at_server/pull/2744)
   **MERGED 2026-08-11** — ⚠️ *this line read "is open for review" until the
   2026-08-14 wrap-up; verified with `gh pr view 2744 --repo
   atsign-foundation/at_server`.* ⚠️ **And the `5bc3618a` this paragraph named
   as at_server's head is long superseded** — it is an ancestor of
   `origin/trunk` now, i.e. landed. ⚠️ **Do not read a SHA here as "at_server's
   head" at all:** `6a86fbcc`, cited elsewhere in this plan for the PoP
   contract, is the tip of the local `gkc-add-apskLegacy-field` branch and is
   *also* an ancestor of trunk; `origin/trunk` itself was at `fdb78568` on
   2026-08-14 and moves independently of anything here. Re-derive with
   `git -C ~/dev/atsign/repos/at_server rev-parse --short origin/trunk`; none
   of this is visible from inside at_client_sdk, which is how both errors
   survived.

   **What this still leaves owed:** at_server's own **210/210** was measured at
   `ab38b884`, several commits back and against a different at_commons source.
   **That number is stale twice over and has to be re-earned before it is cited
   again** — it is at_server's pack, not at_client_sdk's, so none of this
   project's runs discharge it.
2. ~~**Ruling 7's remaining half: flat → typed.**~~ **DONE 2026-08-13**, and
   narrowed on evidence — see [14.18](../implementation-plan.md#1418-the-remaining-d1-initial-development-sequence)
   step 10 and the amendment in [`decisions.md` 91.3](decisions.md#913-the-rulings)
   ruling 7. The projection cannot be **materialised**, so "nothing reads them"
   became "one place reads them": `AtKeys.authenticationFor` /
   `authenticationAlgorithmFor`. ⚠️ **The reader list above was wrong on two of
   its four entries.** `file_io.dart` touches no `AtKeys` flat field at all —
   its only `atKeys.*` uses are `atsign` and `toJson` — and `onboarding_mint.dart`
   *writes* them at mint time, which is the projection working as intended
   rather than a read to move. The two that did move are `AtKeys.toAtChops()`'s
   callers in `at_auth_impl.dart` and, not on the list, `at_client_impl.dart`.
3. ~~**The wire half, client side — none of it exists.**~~ ⚠️ **STOP — this
   whole item is a 2026-08-11 SNAPSHOT and four of its five sub-bullets are now
   FALSE.** Corrected 2026-08-13 after a context-free read of the handoff
   reported that a reader sent here for the step-17 spec would conclude the
   multi-signature writer and the strength order were still owed, and rebuild
   them. **What actually landed** ([14.18](../implementation-plan.md#1418-the-remaining-d1-initial-development-sequence)
   is authoritative, not this list):

   - the `_apsk` **array composer and reader** — steps 6 and 13;
   - the **multi-signature envelope** — step 15. `signEnvelope` takes
     `required List<ApkamSigningKeys> keys` and emits one entry per key;
   - **`requireAlg` no longer exists in any source file** (step 8 replaced the
     refusal with algorithm *resolution*; the only surviving mention is
     `packages/at_client/CHANGELOG.md`). Any line below citing it, or citing
     `envelope_signature.dart:577`, is describing deleted code;
   - the **strength order** — step 7. `SigningAlgoType.strongestFirst` is at
     `packages/at_chops/lib/src/algorithm/algo_type.dart:37`, with
     `packages/at_chops/test/signing_strength_test.dart` as its tripwire, so
     UC-G1.7 has had something to run against since 2026-08-13;
   - the **`enroll:update` caller** — step 16.

   ⚠️ **The line numbers below are also stale** — `ApkamSigningKeys` is no
   longer at `envelope_signature.dart:197`, and `signingKeys` is at
   `apkam_signing.dart:124` returning `Future<List<ApkamSigningKeys>>`, not at
   `:56`. **Nothing is owed from this item any more** — the in-use signing set
   landed 2026-08-13 as step 17, mint-on-demand as step 18, and row B3 moved
   the mint ahead of the enrollment submission on 2026-08-14. (This line read
   "only mint-on-demand is genuinely still owed" until that sweep.) The original text is kept below
   because its *reasoning* about why each piece is an inversion rather than an
   addition is still worth reading — but read it as history, and verify every
   claim against the source before acting on it.

   - **The `_apsk` array composer and reader.** Today `publishPublicSigningKey`
     (`apkam_signing.dart:38`) `put`s a **single bare key**, and does so only
     when the record is absent — a get-then-put-if-missing. Nothing composes
     `{v:1, keys:[{use, alg, pub, status}]}` and nothing reads it. The
     `use`/`alg`/`pub` vocabulary exists in the tree, but in `key_package.dart`
     (the **KEM** package, a different record) and as `[{alg, pub}]` in
     `pq_signing_root.dart` (the signing root, no `use`, no `status`). ⚠️ ~~**Open
     question when the composer lands:** does `publishPublicSigningKey` retire,
     or does it stay and become a second writer to a record the approval path
     also writes? Its skip-if-present means an enrollment that already published
     a bare string never rewrites it.~~ **ANSWERED by [14.18](../implementation-plan.md#1418-the-remaining-d1-initial-development-sequence)
     step 13 — it stays**, as the only writer for an `_apsk` no `enroll:request`
     can carry (a client with no enrollment publishes under `primary`, which has
     no enrollment record). And the skip-if-present is gone: it **republishes on
     a change**, which was a real defect — a rotated key never reached the
     atServer and every envelope signed with the new one verified against the
     old.
   - **The multi-signature envelope. This is an inversion, not an addition.**
     `signEnvelope` emits exactly one `signature` and one `signingAlgo` from a
     `switch` on a single `SigningAlgoType`, on both the v1 and JWS paths. The
     verifier does not merely lack multi-signature support — it **actively
     refuses** a mismatch, via `requireAlg` at `envelope_signature.dart:577`,
     whose message reads *"the published `_apsk` is a `<algo>` key"*. The
     singular is baked into the behaviour and the diagnostic, so this work
     changes an existing refusal rather than extending a permissive path.
   - ~~**The strength order** beside `SigningAlgoType` in at_chops, with its
     raw-literal tripwire~~ — ✅ **BUILT 2026-08-13** as [14.18 step 7](../implementation-plan.md#1418-the-remaining-d1-initial-development-sequence):
     `SigningAlgoType.strongestFirst` and `strongestOf` at
     `packages/at_chops/lib/src/algorithm/algo_type.dart:37`, with
     `packages/at_chops/test/signing_strength_test.dart` as the tripwire, and
     [UC-G1.7](../acceptance.md#16-g1--signature-agility-and-the-rollout-matrix)
     ("the verifier takes the strongest and does not fall back") reads PROVEN in
     the catalogue. This bullet said "no ordering exists anywhere in at_chops or
     at_client today" for 5 days after it shipped, which left the plan claiming
     an at_chops obligation it did not have.
   - ~~**The `enroll:update` caller** and its PoP signature~~ — ✅ **BUILT
     2026-08-13** as [14.18 step 16](../implementation-plan.md#1418-the-remaining-d1-initial-development-sequence):
     `AtEnrollment.update`, `EnrollmentUpdateRequest`, `EnrollmentUpdater` and
     `apkamPossessionSignature` (`AtSigningMode.pkam`, SHA-256 — ruling 14, and
     `AtSigningMode.data` cannot work). ⚠️ A rotation is not persisted anywhere,
     [14.19 item 11](../implementation-plan.md#1419-small-items-raised-2026-08-12-and-not-yet-acted-on).
   - ~~**The in-use signing set** on `AtClientPreference`~~ — ✅ **BUILT
     2026-08-13** as [14.18 step 17](../implementation-plan.md#1418-the-remaining-d1-initial-development-sequence):
     `dataSigningKeyAlgorithms`, defaulted from `PqPosture`. The deprecated
     `signingAlgoType` stays where it is — it is the *authentication* key's
     algorithm, a different thing.
   - **Mint-on-demand** when the in-use set names an algorithm the enrollment
     lacks.

   ⚠️ **Neither side of rollout 1 exists yet.** The staging in
   [`design.md` 9](../design.md#9-subsystem-g--signature-agility-the-authsigning-key-split)
   has rollout 1 ship *reader* capability ungated, before any writer emits the
   array — but the client has neither reader nor writer, so the first
   deliverable here is the reader, not the composer, however tempting it is to
   build the thing that produces output you can look at.

   ⚠️ **The writer half is blocked on owed item 2, and the reader half is not.**
   Found 2026-08-11 by reading the source, and it changes the order this entry
   should be worked in:

   - A **reader** needs the published `_apsk` array and the envelope, both
     fetched over the wire. It touches no local key material, so nothing gates
     it. Start here.
   - A **writer** emitting multi-signature envelopes needs one signing keypair
     **per algorithm**, and nothing can supply that today.
     `ApkamSigningKeys` (`envelope_signature.dart:197`) holds exactly one pair
     of `String`s; `signingKeys` (`apkam_signing.dart:56`) reads it out of
     `atChops`, which carries only the APKAM *authentication* keypair; and
     `AtKeys.toAtChopsForEnrollment` (`at_keys.dart:498`) builds that same
     single authentication pair. **Nothing anywhere enumerates an enrollment's
     signing keys per algorithm** — the accessor that would front the array
     does not exist. Sourcing per-algorithm material
     means sourcing from `AtKeys`, and `apkam_signing.dart`'s own dartdoc
     records why that cannot land yet: *"it cannot land until every client has
     an `AtKeysIo` — today it is nullable and most apps supply none, so reading
     through it would break them."* `_atKeysIo` is indeed `AtKeysIo?`
     (`at_client_impl.dart:80`) and honoured only on first construction.
     ⚠️ **Amended 2026-08-13: that quoted dartdoc is now half wrong, and it is
     still in the file.** The claim was measured — 0 of 22 repos on disk
     supplied one — but the cause was one SDK line, and
     [14.18](../implementation-plan.md#1418-the-remaining-d1-initial-development-sequence) step 11 fixed
     it, so an `at_onboarding_cli` client has a source now. What survives is
     that an app building its own client still supplies none *and is entitled
     to*: a source-less client is a deliberate, tested property protecting the
     cicd atServers. So the accessor needs a defined answer for "no source"
     rather than a precondition that there always is one. Rewriting the dartdoc
     is part of step 12.

     ✅ **Resolved 2026-08-13 by step 12.** `AtKeys.signingKeysFor` enumerates
     an enrollment's signing keys per algorithm, and `ApkamSigning.signingKeys`
     is a `Future<List<ApkamSigningKeys>>` sourced from the keyfile. The "no
     source" answer is the APKAM authentication keypair, which is also the
     answer while nothing files signing material — so the accessor is live
     rather than waiting on a writer, and `now`-posture envelopes are
     unchanged. The stale dartdoc is rewritten.

   So **owed item 2 is not merely the largest remaining piece, it is the gate on
   this one** — which is the argument for doing it before the composer, and the
   reason a session that starts with "compose the array" will not finish it.
4. ~~**The rollout axis.**~~ **DONE 2026-08-13** as
   [14.18](../implementation-plan.md#1418-the-remaining-d1-initial-development-sequence) step 19, and
   built out further by rows B1 and B3 on 2026-08-14. ⚠️ **This item read "the
   axis has no name yet" until 2026-08-18, and had been false for five days.**
   The axes are `PqPosture.authenticationKeyAlgorithm` and
   `PqPosture.dataSigningKeyAlgorithms`, each overridable on
   `AtClientPreference`, and read in production by `self_retrofit.dart`,
   `signing_key_minting.dart` and the `_apsk` composer. They were one enum,
   `SigningRollout` (`now`/`rollout1`/`rollout2`), until
   [ruling 113](decisions.md#113-pqposture-three-postures-and-the-rollout-they-drive-2026-08-18)
   split them. Its premise was wrong as well as its status: the stage does
   **not** switch three flags. Only minting is a decision; the array form and
   the second signature are consequences of how many keys the keyfile holds,
   and the posture supplies one default,
   `AtClientPreference.dataSigningKeyAlgorithms`.
   [`design.md` 9.7](../design.md#9-subsystem-g--signature-agility-the-authsigning-key-split)
   has said so since it was written, which is where this row should have been
   checked against.
5. **The rollout harness — the data path is built; the envelope grid is owed.**
   ⚠️ **This item read as wholly owed, and named a 3×3, until 2026-08-18.**
   Built as [14.18](../implementation-plan.md#1418-the-remaining-d1-initial-development-sequence) steps
   20–22: the two stage-parameterised executables are `tests/pq_matrix/`
   (`scenario/`, `current/`, `published/`), driven by
   `tests/at_functional_test/test/pq_rollout_matrix_test.dart` as a **4×4**
   matrix over `published`/`legacy`/`pqReady`/`pqActive`. All sixteen cells pass,
   and the "failing cell asserted by its specific error" this row asks for no
   longer exists — both cells were measured out of existence on 2026-08-14 and
   [`acceptance.md` 16.5](../acceptance.md#165-the-rollout-matrix) records what it
   used to say.

   ✅ **The signed-envelope grid closed it the same day.** It was the one piece
   of this row genuinely owed — the 4×4 does not touch the envelope path at all
   (`git grep 'wrapAndSign\|signEnvelope\|verifyEnvelope' -- tests/pq_matrix`
   returned nothing, against `EnvelopeSigning` as a positive control), so the
   sixteen green cells were not evidence about envelope verification. Built as
   UC-G1.15: nine cells over `legacy`/`pqReady`/`pqActive`, each signing at the
   sender's stage and verifying at the receiver's through a real `_apsk` fetch.
   It is a 3×3 rather than a fourth row and column because a released client and
   this tree cannot exchange an envelope in either direction under any stage.

   **`pqActive → pqReady` passes**, which is what turns
   [`decisions.md` 108](decisions.md#108-the-signing-rollout-swaps-algorithms-it-never-overlaps-them-2026-08-18)
   from a ruling into a measurement: strongest signer, weakest verifier, and no
   overlap needed because verification is ungated.

   ⚠️ **The nine cells are not what proves the stages differ, and this is
   measured rather than argued.** Mutating `pqActive` to resolve as `pqReady`
   leaves **all nine passing** — a sender signing RSA-2048 verifies everywhere
   too. What catches it is the algorithm assertion: `pqActive → pqActive` must
   be exactly `['ML-DSA-65']`, `legacy → legacy` must not contain it. Both arms
   in one
   session: the mutation reddens naming `['RS256']`, the revert is green.
   The envelope half lives in `current/lib/envelope_exchange.dart`, not the
   shared scenario, because 3.14.0's `wrapAndSign` returns a `Map` where this
   tree's returns a `SignedEnvelope` and 3.14.0 ships no `lib/src/signing/` —
   a shared file would not compile on the published arm.
6. ~~**`enroll:update` parity across atServer implementations.**~~
   ⛔ **OUT OF SCOPE — gkc, 2026-08-18.** Do not re-raise it, and do not file a
   tracking issue for it. Recorded here rather than deleted because it was
   raised three times in one session, each time from re-reading this row as
   owed.

⚠️ **"Still owed: an `mldsa65` arm on the rotation tests" was struck 2026-08-18.**
The sentence dated from 2026-08-11 and the arm has since been written:
`packages/at_auth/test/enrollment_update_test.dart` carries both algorithms (15
`rsa2048` mentions, 10 `mldsa65`), and `signing_key_minting_test.dart` covers
the mint-and-retire path under `mldsa65`. The reasoning it recorded is still
right — picking `rsa2048` for a fixture is the choice that makes a wrong answer
invisible — which is why it is struck here rather than deleted.

---

#### 14.17's 2026-08-11 original, kept whole

Until 2026-08-22 this section existed **twice** — here and in the live plan —
and the two had diverged. The live copy was headed *"complete"*; this one
*"what is built, and what is owed"*, and each carried roughly ninety lines the
other did not. The merged text above takes the live copy as the successor,
because it strikes each superseded claim in place and says what it used to
claim.

What follows is the original **in full, unedited**. It is dated evidence, not
current state, and several of its statements are ones the text above
explicitly reverses — most visibly items 4, 5 and 6 of its owed list, and its
closing *"Still owed: an `mldsa65` arm on the rotation tests"*, which was
struck on 2026-08-18. It is kept whole rather than excerpted because a first
attempt at this merge hand-picked three blocks and silently dropped 56 lines
of measured evidence, which is the failure this project keeps recording.


The design landed 2026-08-11 as [`decisions.md` 91](decisions.md#91-signature-agility-the-apkam-auth-key-stops-being-the-enrollments-signing-key-2026-08-11),
[`design.md` 9](../design.md#9-subsystem-g--signature-agility-the-authsigning-key-split)
and [`acceptance.md` 16](../acceptance.md#16-g1--signature-agility-and-the-rollout-matrix).
This entry is the owed half; the rulings are the contract.

**Built and verified.**

| Piece | Where | Rails |
|-------|-------|-------|
| `EnrollParams.apsk`, `.apkamPublicKeySignature`, `EnrollOperationEnum.update` + grammar | **at_commons 5.14.0, published 2026-08-11**; [#2137](https://github.com/atsign-foundation/at_client_sdk/pull/2137) merged to trunk and merged into the spike | at_commons 512/512, analyze 0 |
| `enroll:update` handler, PoP verification, and storing a client-composed `_apsk` verbatim | at_server `gkc-apsk-auto-publish` `ab38b884` | 919/919 unit, **210/210 functional** — ⚠️ two caveats below |
| Auth/signing key types, generation keyIds, status-aware invariants, `replaceKey`, `activeEnrollmentId`, pure-legacy `toJson` | at_client_sdk `gkc-pq-d1-spike` | at_auth 241/241, analyze 0 |
| The above **plus trunk**, after merge `95584f818` | at_client_sdk `gkc-pq-d1-spike` | at_chops 527/527, at_commons 512/512, at_auth 241/241, at_client 1186/1186, at_onboarding_cli 38/38, at_lookup + at_policy green; analyze **0 errors and 0 warnings** across seven packages |

⚠️ **Two caveats on the at_server row, because "built" is doing less work there
than it looks** (both re-verified against the source 2026-08-11):

- **The capability is dormant.** *Nothing* in `at_client`, `at_auth` or
  `at_onboarding_cli` assigns `EnrollParams.apsk` — grep for `.apsk =` returns
  nothing. The atServer will store a client-composed array and no client
  composes one, so today's clients still publish the legacy bare key through
  `publishPublicSigningKey` (`apkam_signing.dart:38`). That is the intended
  sequencing, not a defect, but it means **no end-to-end exercise exists** and
  will not until owed item 3 lands.
- **The 210/210 drove `enroll:update` with hand-built payloads**, not the output
  of a real client. The rows prove the handler, the PoP check and the storage;
  they prove nothing about a composer that does not exist yet.

- ⚠️ Also measured with at_commons resolved through the `at_commons-apsk-1`
  tag, so the number does **not** carry over the override swap in owed item 1.

**Owed, in dependency order.**

1. ~~**Drop at_server's at_commons override.**~~ **DONE 2026-08-11.** The
   override is out of both `pubspec.yaml` and `pubspec_overrides.yaml`,
   `pubspec.lock` resolves at_commons from hosted 5.14.0, the
   `at_commons-apsk-1` tag is deleted local and origin (its commit `54ccffdd0`
   is an ancestor of trunk, so nothing was orphaned), and
   [at_server#2744](https://github.com/atsign-foundation/at_server/pull/2744)
   **MERGED 2026-08-11** — ⚠️ *this line read "is open for review" until the
   2026-08-14 wrap-up; verified with `gh pr view 2744 --repo
   atsign-foundation/at_server`.* ⚠️ **And the `5bc3618a` this paragraph named
   as at_server's head is long superseded** — it is an ancestor of
   `origin/trunk` now, i.e. landed. ⚠️ **Do not read a SHA here as "at_server's
   head" at all:** `6a86fbcc`, cited elsewhere in this plan for the PoP
   contract, is the tip of the local `gkc-add-apskLegacy-field` branch and is
   *also* an ancestor of trunk; `origin/trunk` itself was at `fdb78568` on
   2026-08-14 and moves independently of anything here. Re-derive with
   `git -C ~/dev/atsign/repos/at_server rev-parse --short origin/trunk`; none
   of this is visible from inside at_client_sdk, which is how both errors
   survived.

   **What this still leaves owed:** at_server's own **210/210** was measured at
   `ab38b884`, several commits back and against a different at_commons source.
   **That number is stale twice over and has to be re-earned before it is cited
   again** — it is at_server's pack, not at_client_sdk's, so none of this
   project's runs discharge it.
2. ~~**Ruling 7's remaining half: flat → typed.**~~ **DONE 2026-08-13**, and
   narrowed on evidence — see [14.18](#1418-the-remaining-d1-initial-development-sequence)
   step 10 and the amendment in [`decisions.md` 91.3](decisions.md#913-the-rulings)
   ruling 7. The projection cannot be **materialised**, so "nothing reads them"
   became "one place reads them": `AtKeys.authenticationFor` /
   `authenticationAlgorithmFor`. ⚠️ **The reader list above was wrong on two of
   its four entries.** `file_io.dart` touches no `AtKeys` flat field at all —
   its only `atKeys.*` uses are `atsign` and `toJson` — and `onboarding_mint.dart`
   *writes* them at mint time, which is the projection working as intended
   rather than a read to move. The two that did move are `AtKeys.toAtChops()`'s
   callers in `at_auth_impl.dart` and, not on the list, `at_client_impl.dart`.
3. ~~**The wire half, client side — none of it exists.**~~ ⚠️ **STOP — this
   whole item is a 2026-08-11 SNAPSHOT and four of its five sub-bullets are now
   FALSE.** Corrected 2026-08-13 after a context-free read of the handoff
   reported that a reader sent here for the step-17 spec would conclude the
   multi-signature writer and the strength order were still owed, and rebuild
   them. **What actually landed** ([14.18](#1418-the-remaining-d1-initial-development-sequence)
   is authoritative, not this list):

   - the `_apsk` **array composer and reader** — steps 6 and 13;
   - the **multi-signature envelope** — step 15. `signEnvelope` takes
     `required List<ApkamSigningKeys> keys` and emits one entry per key;
   - **`requireAlg` no longer exists in any source file** (step 8 replaced the
     refusal with algorithm *resolution*; the only surviving mention is
     `packages/at_client/CHANGELOG.md`). Any line below citing it, or citing
     `envelope_signature.dart:577`, is describing deleted code;
   - the **strength order** — step 7. `SigningAlgoType.strongestFirst` is at
     `packages/at_chops/lib/src/algorithm/algo_type.dart:37`, with
     `packages/at_chops/test/signing_strength_test.dart` as its tripwire, so
     UC-G1.7 has had something to run against since 2026-08-13;
   - the **`enroll:update` caller** — step 16.

   ⚠️ **The line numbers below are also stale** — `ApkamSigningKeys` is no
   longer at `envelope_signature.dart:197`, and `signingKeys` is at
   `apkam_signing.dart:124` returning `Future<List<ApkamSigningKeys>>`, not at
   `:56`. **Nothing is owed from this item any more** — the in-use signing set
   landed 2026-08-13 as step 17, mint-on-demand as step 18, and row B3 moved
   the mint ahead of the enrollment submission on 2026-08-14. (This line read
   "only mint-on-demand is genuinely still owed" until that sweep.) The original text is kept below
   because its *reasoning* about why each piece is an inversion rather than an
   addition is still worth reading — but read it as history, and verify every
   claim against the source before acting on it.

   - **The `_apsk` array composer and reader.** Today `publishPublicSigningKey`
     (`apkam_signing.dart:38`) `put`s a **single bare key**, and does so only
     when the record is absent — a get-then-put-if-missing. Nothing composes
     `{v:1, keys:[{use, alg, pub, status}]}` and nothing reads it. The
     `use`/`alg`/`pub` vocabulary exists in the tree, but in `key_package.dart`
     (the **KEM** package, a different record) and as `[{alg, pub}]` in
     `pq_signing_root.dart` (the signing root, no `use`, no `status`). ⚠️ ~~**Open
     question when the composer lands:** does `publishPublicSigningKey` retire,
     or does it stay and become a second writer to a record the approval path
     also writes? Its skip-if-present means an enrollment that already published
     a bare string never rewrites it.~~ **ANSWERED by [14.18](#1418-the-remaining-d1-initial-development-sequence)
     step 13 — it stays**, as the only writer for an `_apsk` no `enroll:request`
     can carry (a client with no enrollment publishes under `primary`, which has
     no enrollment record). And the skip-if-present is gone: it **republishes on
     a change**, which was a real defect — a rotated key never reached the
     atServer and every envelope signed with the new one verified against the
     old.
   - **The multi-signature envelope. This is an inversion, not an addition.**
     `signEnvelope` emits exactly one `signature` and one `signingAlgo` from a
     `switch` on a single `SigningAlgoType`, on both the v1 and JWS paths. The
     verifier does not merely lack multi-signature support — it **actively
     refuses** a mismatch, via `requireAlg` at `envelope_signature.dart:577`,
     whose message reads *"the published `_apsk` is a `<algo>` key"*. The
     singular is baked into the behaviour and the diagnostic, so this work
     changes an existing refusal rather than extending a permissive path.
   - ~~**The strength order** beside `SigningAlgoType` in at_chops, with its
     raw-literal tripwire~~ — ✅ **BUILT 2026-08-13** as [14.18 step 7](../implementation-plan.md#1418-the-remaining-d1-initial-development-sequence):
     `SigningAlgoType.strongestFirst` and `strongestOf` at
     `packages/at_chops/lib/src/algorithm/algo_type.dart:37`, with
     `packages/at_chops/test/signing_strength_test.dart` as the tripwire, and
     [UC-G1.7](../acceptance.md#16-g1--signature-agility-and-the-rollout-matrix)
     ("the verifier takes the strongest and does not fall back") reads PROVEN in
     the catalogue. This bullet said "no ordering exists anywhere in at_chops or
     at_client today" for 5 days after it shipped, which left the plan claiming
     an at_chops obligation it did not have.
   - ~~**The `enroll:update` caller** and its PoP signature~~ — ✅ **BUILT
     2026-08-13** as [14.18 step 16](#1418-the-remaining-d1-initial-development-sequence):
     `AtEnrollment.update`, `EnrollmentUpdateRequest`, `EnrollmentUpdater` and
     `apkamPossessionSignature` (`AtSigningMode.pkam`, SHA-256 — ruling 14, and
     `AtSigningMode.data` cannot work). ⚠️ A rotation is not persisted anywhere,
     [14.19 item 11](#1419-small-items-raised-2026-08-12-and-not-yet-acted-on).
   - ~~**The in-use signing set** on `AtClientPreference`~~ — ✅ **BUILT
     2026-08-13** as [14.18 step 17](#1418-the-remaining-d1-initial-development-sequence):
     `dataSigningKeyAlgorithms`, defaulted from `PqPosture`. The deprecated
     `signingAlgoType` stays where it is — it is the *authentication* key's
     algorithm, a different thing.
   - **Mint-on-demand** when the in-use set names an algorithm the enrollment
     lacks.

   ⚠️ **Neither side of rollout 1 exists yet.** The staging in
   [`design.md` 9](../design.md#9-subsystem-g--signature-agility-the-authsigning-key-split)
   has rollout 1 ship *reader* capability ungated, before any writer emits the
   array — but the client has neither reader nor writer, so the first
   deliverable here is the reader, not the composer, however tempting it is to
   build the thing that produces output you can look at.

   ⚠️ **The writer half is blocked on owed item 2, and the reader half is not.**
   Found 2026-08-11 by reading the source, and it changes the order this entry
   should be worked in:

   - A **reader** needs the published `_apsk` array and the envelope, both
     fetched over the wire. It touches no local key material, so nothing gates
     it. Start here.
   - A **writer** emitting multi-signature envelopes needs one signing keypair
     **per algorithm**, and nothing can supply that today.
     `ApkamSigningKeys` (`envelope_signature.dart:197`) holds exactly one pair
     of `String`s; `signingKeys` (`apkam_signing.dart:56`) reads it out of
     `atChops`, which carries only the APKAM *authentication* keypair; and
     `AtKeys.toAtChopsForEnrollment` (`at_keys.dart:498`) builds that same
     single authentication pair. **Nothing anywhere enumerates an enrollment's
     signing keys per algorithm** — the accessor that would front the array
     does not exist. Sourcing per-algorithm material
     means sourcing from `AtKeys`, and `apkam_signing.dart`'s own dartdoc
     records why that cannot land yet: *"it cannot land until every client has
     an `AtKeysIo` — today it is nullable and most apps supply none, so reading
     through it would break them."* `_atKeysIo` is indeed `AtKeysIo?`
     (`at_client_impl.dart:80`) and honoured only on first construction.
     ⚠️ **Amended 2026-08-13: that quoted dartdoc is now half wrong, and it is
     still in the file.** The claim was measured — 0 of 22 repos on disk
     supplied one — but the cause was one SDK line, and
     [14.18](#1418-the-remaining-d1-initial-development-sequence) step 11 fixed
     it, so an `at_onboarding_cli` client has a source now. What survives is
     that an app building its own client still supplies none *and is entitled
     to*: a source-less client is a deliberate, tested property protecting the
     cicd atServers. So the accessor needs a defined answer for "no source"
     rather than a precondition that there always is one. Rewriting the dartdoc
     is part of step 12.

     ✅ **Resolved 2026-08-13 by step 12.** `AtKeys.signingKeysFor` enumerates
     an enrollment's signing keys per algorithm, and `ApkamSigning.signingKeys`
     is a `Future<List<ApkamSigningKeys>>` sourced from the keyfile. The "no
     source" answer is the APKAM authentication keypair, which is also the
     answer while nothing files signing material — so the accessor is live
     rather than waiting on a writer, and `now`-posture envelopes are
     unchanged. The stale dartdoc is rewritten.

   So **owed item 2 is not merely the largest remaining piece, it is the gate on
   this one** — which is the argument for doing it before the composer, and the
   reason a session that starts with "compose the array" will not finish it.
4. **The rollout axis.** One `PqPosture` flag switching all three writer
   behaviours together (mint signing keys, publish the array, emit
   multi-signature envelopes). **The axis has no name yet** — see
   [`design.md` 9.7](../design.md#9-subsystem-g--signature-agility-the-authsigning-key-split).
5. **The rollout harness.** Two stage-parameterised executables plus the 3×3
   matrix in [`acceptance.md` 16.5](../acceptance.md#16-g1--signature-agility-and-the-rollout-matrix),
   with the failing cell asserted by its specific error.
6. **`enroll:update` parity across atServer implementations** — needs
   its own tracking issue so it cannot silently diverge.

**Unverified, and not to be reported as verified.** Two at_client_sdk
functional files were edited for the new keyId shape and have only been
analyzed, never run — `tests/at_functional_test/test/pq_native_onboard_live_test.dart`
and `tests/at_onboarding_cli_functional_tests/test/pq_native_onboard_test.dart`.
They need at_client_sdk's own recycled VE.

**The spike carries trunk as of 2026-08-11** (merge `95584f818`, trunk
`2e98fdd9d`, 87 commits). What that merge settled, because a stale version
number here would misroute a release:

- **at_chops is 3.6.0 and at_commons is 5.15.0 on the spike.** trunk published
  at_chops 3.5.0 and at_commons 5.14.0 the same day, and the spike had been
  claiming both numbers for entirely different, unreleased content. Both sides
  writing the same string meant `pubspec.yaml` auto-merged with no conflict at
  all — the collision was silent, and the published CHANGELOG headings now hold
  trunk's content with the spike's moved up a minor. at_client's floors follow.
- **trunk's PQ length validation now lives where the spike's refactor put the
  work.** trunk added checks to `MlKem768PureDartAlgo` and
  `MlDsa65PureDartAlgo` bodies that the spike had already refactored away, so
  taking either side alone silently dropped something. The ML-KEM checks moved
  into `MlKemPureDart` against per-level size getters — 768's constants in a
  base that also serves ML-KEM-1024 would reject every well-formed 1024 key —
  and the ML-DSA checks into `signBytesSync`/`verifyBytesSync`, which the PKAM
  dispatch and envelope signing reach directly and would otherwise bypass.
- **Widening an enum broke a pin in a file no one had touched.** trunk's new
  `at_auth/test/atkey_material_test.dart` pins both `known` sets exactly; the
  spike had added `mlkem1024`, `privateAuthentication` and
  `publicAuthentication`. Git merged that file cleanly and it went red only on
  a test run.

**Two red unit tests predated the merge and were fixed after it** (`b9f94ab05`,
`e752d5529`), both stale tests rather than product defects, and both proven
pre-existing by running the same files at the pre-merge head in a worktree.
`signing_algo_resolution_test.dart` built its fixture from `privateSigning`,
which predates the auth/signing split, so `signingAlgorithmForEnrollment`
correctly found no authentication material and fell back to `rsa2048`.
`at_onboarding_cli`'s `keyfile_literal_pins_test.dart` still expected
`version`/`atsign`/`keys` from a keyset with no typed material — the guard for
an at_auth change living one package away, which is why nothing went red where
the change landed. Neither was covered by the previous entry's rails line,
because that line reported at_onboarding_cli as *analyze* clean and at_client's
unit suite had not been run.

**A latent defect the tests chose not to find, 2026-08-11.** The `enroll:update`
proof-of-possession check read `AtChopsImpl.verify(...).result` directly, but
that is a `FutureOr<bool>` and published at_chops 3.5.0 verifies `mldsa65`
**asynchronously** — so a rotation to an ML-DSA key died on
`type 'Future<bool>' is not a subtype of type 'bool'`. Both the unit and the
functional tests exercised `rsa2048`, which verifies synchronously, so the whole
suite passed over it. Fixed by awaiting the result (at_server 3.16.0 CHANGELOG).
**Still owed: an `mldsa65` arm on the rotation tests** — the algorithm the
feature exists for is the one arm nothing covers, and picking `rsa2048` for a
fixture is exactly the choice that makes a wrong answer invisible.

**Three rulings were wrong until execution proved it,** each caught by a test
rather than by review, and each amended in place with what it used to say:
ruling 14's signing mode (`AtSigningMode.data` signs with the *encryption*
keypair, so proof of possession was structurally impossible as specified),
ruling 4's uniqueness (scoped per role it permitted exactly one signing
algorithm, defeating the agility the work exists for), and ruling 3 (a second
retrofit now throws, replacing a deliberate per-algorithm idempotency). Three
of sixteen rulings is the argument for proving the whole sequence on the spike
before chunking it into PRs.


---

## 15. The lettered D1 gates (G0–G8), as they were discharged

Demoted here on 2026-08-26, when the live plan collapsed to one prioritised
list. `## THE NEXT MOVE` carried a second ranked list of lettered gates alongside
the `## TODO` table; the two drifted, and the letter list twice carried two
`[RECOMMENDED]` markers at once. Every gate that was still owed became a P0 or P1
row in the live plan. What follows is each entry as it stood, kept because a
reader who deletes it re-derives the diagnoses, the measurements and the
instrument faults from scratch.

### G0 — an atServer answered concurrent cross-atSign lookups with each other's records

**G0. ✅ DISCHARGED 2026-08-25 — an atServer answered concurrent cross-atSign
lookups with each other's records.** Nothing here is startable: the fix is on
at_server trunk. The entry is kept for the same reason G2's is — it carries the
diagnosis, the measurements, the controls and the three instrument faults, and
the deferred pooling discussion in [`## TODO`](../implementation-plan.md#todo) is written against it.

The defect, in an atServer that predates the fix: two `lookup:` requests for
different records of the same peer atSign, in flight at the same moment on one
atServer, can each come back carrying the other's record — **with no exception
raised**, so an app receives a well-formed record that is not the one it asked
for. Nothing is stored wrongly; the record at rest is correct at both ends.

⚠️ **This entry read "A conveyance payload is landing at VALUE record
addresses" until 2026-08-24, and that was wrong.** The write was never at
fault. `llookup:all:` on the sender's own atServer and `lookup:all:` from the
receiver both return the correct 6668-byte value for the very record whose read
had just handed back a 44-character content key. What the earlier entry read as
a misplaced payload was one read being answered with another read's response.

**It is not a PQ defect.** PQ made it visible: an nskey read issues a *second*
cross-atSign lookup, for the `<ckKid>.__ck` conveyance, from inside the first
one's decrypt — so a single `get` puts two relayed lookups in flight where a
legacy read has one. (Why legacy never surfaced it is untested; I have not
measured a legacy arm.)

⛔ **BOTH HARNESSES WERE DELETED on 2026-08-26** (gkc), once the atServer fix
was merged and shipping: they reproduce nothing against a fixed atServer, which
is what they were for. The commands and measurements below are therefore a
RECORD, not instructions — `test/concurrent_relayed_lookup_test.dart` and
`test/pq_read_returns_another_record_test.dart` no longer exist. ⚠️ **What went
with them is the only fast way to tell a fixed atServer from an unfixed one**;
recover them from git history if that question ever needs asking again, rather
than rewriting them from this prose.

**The standalone probe, as it was — it had no PQ in it at all:**

```bash
docker rm -f test-virtualenv-1        # recycle the VE first, always
cd tests/at_functional_test
VIRTUALENV_IMAGE=at_virtual_env:local ./runLocal.sh   # or bring the VE up alone
dart test test/concurrent_relayed_lookup_test.dart --concurrency=1 --run-skipped
```

Four sockets on `@bob🛠`, four different records of `@alice🛠`, asked together.
`tests/at_functional_test/test/pq_read_returns_another_record_test.dart` is the PQ symptom
this was found through, at 13-22 wrong reads per 50 cycles, and it clears
under the fix — see the table below. ⛔ It must run FIRST on a freshly
recycled virtualenv; after this probe in the same one it reads 0.
Measured 2026-08-24 against `at_virtual_env:local`, `@alice🛠` under write load:

| in flight at once | requests | answered correctly | answered with another record | refused or timed out |
| ----------------- | -------- | ------------------ | ---------------------------- | -------------------- |
| 1 (control)       | 120      | 120                | 0                            | 0                    |
| 4                 | 480      | 41                 | 35                           | 404                  |

The refusals name the same event from the other side: 250 `AT0011-Internal
server exception : Connection failed to @alice🛠`, 18 `AT0023-Timeout waiting
for response`, and 16 `AT0003-Invalid syntax` in reply to a `lookup:all:` the
control arm sends cleanly 120 times.

**The mechanism, read in at_server at `a0deee69` and confirmed unchanged on
its trunk at `a37e3e3b`:** ⚠️ **This said `a0deee69` was "the revision
`at_virtual_env:local` was built from", and that was never supported** — see
the note in [Re-deriving the state](../implementation-plan.md#re-deriving-the-state). What matters is
that trunk carries it, which was checked directly.

- `AtCacheManager` holds one `DummyInboundConnection` and passes it to
  `OutboundClientManager.getClient(otherAtSign, thatConnection)` on every
  relayed lookup (`packages/at_secondary_server/lib/src/caching/cache_manager.dart`).
- `OutboundClientPool.get` matches a pooled client with
  `client.inboundConnection.equals(...)`, and `DummyInboundConnection.equals`
  returns true for **any** other `DummyInboundConnection` — so every relayed
  lookup to a given atSign, from every client connection, gets the same
  `OutboundClient` and therefore the same socket. The atServer's own log shows
  it: three `retrieved outbound client to @alice🛠 ... from pool` inside 140 µs.
- `OutboundClient.lookUp` writes its request and reads whatever the listener
  queues next, with **no mutex** across the pair. The client half of the same
  conversation does hold one — `AtLookupImpl._process` keeps
  `requestResponseMutex` across `_sendCommand` + `messageListener.read`.
- `getClient` is not atomic either: two concurrent misses each create and add a
  client, so the pool can hold duplicates for one key (observed, 6 ms apart).

✅ **RULED by gkc 2026-08-24, then REVISED by him the same day. The revision is
what stands.** ⚠️ **This entry recorded "all three, not a choice between them"
and that is superseded** — the pool-key change is OUT, and gkc wants the
question it raises taken on its own:

> "The one thing I'm not sure about is pool-keying the relayed lookup
> connection on the real inbound connection. I think I'd rather serialize on a
> single connection for now, and have a longer discussion on how to handle
> outbound connection pooling and concurrency at a later date"

**In scope:**

1. **Lock `OutboundClient` across each request/response pair.** On its own this
   fixes the swap: the shared client is retained, so relayed lookups queue on
   one socket instead of interleaving on it.
2. **Make `OutboundClientManager.getClient` atomic per pool key**, so two
   concurrent misses stop each creating and adding a client for one key.

**Out of scope, deliberately:** keying the pool on the asking inbound
connection, and `DummyInboundConnection.equals` answering true for any other
dummy. Changing `equals` was never in it —
`NotifyConnectionPool.getOutboundClient` builds a fresh dummy per call and
relies on that match to reuse a connection at all, so identity equality there
would open a connection per notification.

⚠️ **Carry this into that later discussion**: with the shared dummy retained,
every relayed lookup to a given remote atSign now serialises behind every other
one. That is correct and it is a throughput characteristic — and a request
queued on the mutex is waiting *before* its 5 s read budget starts, because the
timeout begins after acquisition.

**Three things the diagnosis did not have, established in at_server at trunk
`a37e3e3b`:**

- `InboundConnectionImpl.equals` matches on remote **address and port**, not
  object identity. So "key the pool on the real inbound connection" would not
  have been the identity keying it sounded like, which is its own reason the
  deferred discussion is the right home for it.
- `NotifyConnectionsPool.getOutboundClient` has the **same non-atomic
  get/connect/add shape** as `OutboundClientManager.getClient`. The ruling
  names only `getClient`.
- `PolVerbHandler` holds a **third** `DummyInboundConnection`, and because any
  dummy matches any other, pol's outbound clients and the relayed-lookup
  clients share one pooled client per atSign at `handshakeRequired: false` —
  so pol's `lookUp`/`plookUp` interleave on the same socket as relayed lookups
  today.

⛔ **A claim in the diagnosis was WRONG, and it is recorded because a lock
design is what rests on it.** This entry said the send/read pairs inside
`_establishHandShake` "run under `connect()` before the client is reachable
from the pool". They do not: `PolVerbHandler` and `ScanVerbHandler` both call
`connect()` on a client they have just taken *from* the pool, behind
`if (!oc.isConnectionCreated)` and `if (!outBoundClient.isHandShakeDone)`
guards that `getClient`'s default `connect: true` normally makes false. Latent
rather than hot, but the stated property does not hold. The lock design
survives for a different reason: `connect()`'s callees are the leaf wire
operations, so locking only those leaves no nesting. ⚠️ **`plookUp` delegates
to `lookUp` and must therefore NOT take the lock itself** — a "lock every
public method" pass deadlocks there.

✅ **VERIFIED END TO END ON THE REAL WIRE, 2026-08-24.** ⚠️ **This continued
"and G0 STAYS OPEN, because nothing is merged"; it merged on 2026-08-25.** Every
atServer built before that merge still carries the defect, which is why the
before-and-after images below are worth keeping rather than deleting.

Two virtualenv images built from named refs, `g0base` from trunk `a37e3e3b` and
`g0fixed` from `af957440`, run minutes apart on one machine with one probe:

| `concurrent_relayed_lookup_test` | g0base | g0fixed |
| -------------------------------- | ------ | ------- |
| width 1 (the control)            | 60/60 ok | 60/60 ok |
| width 4, requests                | 120    | 120     |
| **answered correctly**           | **15** | **120** |
| **answered with another record** | **7**  | **0**   |
| "Internal server exception"      | 54     | 0       |
| "connection went away"           | 26     | 0       |
| "Invalid syntax"                 | 11     | 0       |
| "Timeout waiting for response"   | 7      | 0       |

Zero exceptions of any kind in the fixed arm's whole log. ⚠️ **The baseline
*mix* is approximate and must not be quoted as exact** — the harness tests
message text in a fixed order, so a message carrying two of the phrases lands
in whichever is tested first. The totals, the crossings and the fixed arm's
zeros are solid; zero needs no bucketing.

**What made this readable rather than merely encouraging**, and what to repeat:
the baseline arm was run first and had to fail before the fixed arm could mean
anything; the two compiled `secondary` binaries were `shasum`-compared to prove
the arms differ in the varied thing; and the at_server session wrote its
predictions down *before* seeing any number.

✅ **The PQ symptom clears under the fix too — and the harness is sound.**
⚠️ **This entry said `pq_read_returns_another_record_test.dart` "HAS STOPPED
DISCRIMINATING", and that was wrong.** It discriminates perfectly well; what
had changed was the position I ran it from. Measured across 350 cycles:

| image | at_server ref | ok | wrong | errored |
| ----- | ------------- | -- | ----- | ------- |
| `g0old` | `a0deee69` | 26 / 21 | **17 / 20** | 7 / 9 |
| `dev_env` (what CI runs) | not identifiable | 24 | **19** | 7 |
| `g0base` | trunk `a37e3e3b` | 30 / 11 | **13 / 22** | 7 / 17 |
| `g0fixed` | `af957440` | **50 / 50** | **0 / 0** | **0 / 0** |

Five unfixed runs, 250 cycles, 91 wrong reads. Two fixed runs, 100 cycles,
none. Every run image-asserted — `ve_up.sh` inspects the running container and
refuses if compose fell back to its own default, which is a real trap here.

⛔ **RUN THIS HARNESS FIRST, ON A FRESHLY RECYCLED VIRTUALENV, OR IT READS 0
AND MEANS NOTHING.** Every run that went first reproduced; every run that
followed `concurrent_relayed_lookup_test` in the same virtualenv read 0 wrong —
five and three, cleanly split, on both fixed and unfixed images. That is a
confounder in the *harness rig*, not in any atServer, and it cost two wrong
conclusions before it was found: first that the harness had stopped working,
then that trunk masked the symptom. Neither was true.

**Volume is not the lever, so do not reach for caching.** The atServer issues
essentially the same number of relayed lookups either way — 378 during the PQ
phase in the suppressed position against 408 and 418 when it runs alone, all
counted from `AtCacheManager`'s own `remoteLookUp:` log lines with a positive
control on the same file. The lookups still happen and they stop crossing, so
what narrows is the overlap *window*. **The leading candidate is untested**: in
a clean virtualenv the first relays each wait on an outbound connection being
established and handshaken, which is slow enough for several to pile up on the
shared client, whereas a warmed connection makes each relay short enough that
two are rarely in flight together. That would make the window a property of
connection state rather than of code, and therefore something that can widen
again with no change at all.

⛔ **Ruled out with evidence — do not re-derive any of these:**at_client’s read path (the key asked for is the key returned, and a `CONVEYANCE-FOR-VALUE` probe inside `GetResponseTransformer` never fired); the shared `AtKey` object between put and get (150 cycles, clean); metadata aliasing via `ckConveyanceKey`; `CryptoRuntime._stampEncrypted` colliding with a read (0 shared metadata objects over 15 runs); concurrent nskey seeding (serialising provisioning did **not** help); and the write itself, settled by the raw lookups above. (Moved here 2026-08-25 from the `## TODO` row that used to carry it, so G0 holds the substance and the row holds a pointer.)

⚠️ **Three instrument faults nearly produced confident wrong numbers here, and
two of them look authoritative.** The image-label fault is described in
[Re-deriving the state](../implementation-plan.md#re-deriving-the-state). The second: a fresh git
worktree of at_server resolves `at_server_spec` to **hosted 5.1.0** instead of
the in-tree 5.2.1, because the path override lives only in an **untracked**
melos `pubspec_overrides.yaml` — it compiles clean and analyzes clean, so a
probe run against it would have measured a server nobody built. The third: an
`AT\d{4}` regex buckets nothing on the client side, because the codes are what
the **atServer** puts on the wire and at_client has already rewritten them into
message text by the time a caller sees the exception — one bucket where there
were four.

**Also owed in at_server, and not part of this fix** (both found by being
bitten): `tests/at_functional_test/runLocal.sh` and `tests/at_end2end_test/runLocal.sh`
each `mkdir -p` the `root` contents directory and not the `secondary` one, so
both work in a checkout that has run before and fail on a fresh clone — that
half is **FIXED: at_server
[PR #2772](https://github.com/atsign-foundation/at_server/pull/2772) merged to
trunk on 2026-08-25** as `064640bb`, and both runners now create the directory
(⚠️ this read "open as of 2026-08-25"); and the `at_server_spec` hosted fallback
above, which gkc has deliberately left for a considered decision, is filed
nowhere and reaches CI — its `unit_tests` job
runs `dart pub get` per package with no melos step, so a PR changing
`at_server_spec` and `at_secondary_server` together tests the new server
against the old published spec, green.

**Where the work landed**: **at_server
[PR #2771](https://github.com/atsign-foundation/at_server/pull/2771)**, branch
`gkc-outbound-client-concurrency`, **merged to at_server trunk 2026-08-25** as
merge commit `8f4a985a`. ⚠️ **This paragraph read "open and not merged … what is owed is the
merge"**, and before that "three commits, head `52d63b63` — unpushed as of
2026-08-24". Re-derive rather than trusting
either: `gh pr view 2771 --repo atsign-foundation/at_server`, or
`git -C <at_server> merge-base --is-ancestor af957440 origin/trunk`. The merge
carries four files — `outbound_client.dart`, `outbound_client_manager.dart`,
their CHANGELOG entry, and a new `outbound_client_concurrency_test.dart` —
which is the ruled scope and nothing beyond it. `af957440`, the ref every
measurement above was taken against, is now an ancestor of trunk. Its own
rails: that new concurrency test, the package suite at 1030/1030, and
at_server's two real-wire suites at 239 and 47.

⚠️ **The merge leaves one rig action owed, and nothing performs it
automatically.** `at_virtual_env:local` on this machine is whatever tree last
built it, so it does *not* become a fixed atServer by virtue of the merge —
rebuild it from at_server trunk before anything here trusts that tag again,
using the recipe in [Re-deriving the state](../implementation-plan.md#re-deriving-the-state), and pin the
image explicitly on every live run until then. ⛔ **And "just build trunk" is no
longer a baseline**: trunk carries the fix, so an image built from it is a FIXED
arm. An unfixed control has to come from `a37e3e3b` or from `8f4a985a`'s first
parent — `at_virtual_env:g0base` already is one. The relay probe named above
tells the two apart in seconds and is the only thing that reliably does. No image label can answer "which
at_server code is in this image"; that is the first of the three instrument
faults below.

⚠️ **Also owed, and separate**: at_lookup's
`OutboundMessageListener.read` handles `AT0014 "Unexpected response found"` by
popping one entry off `_queue` and clearing `_buffer` **without draining the
queue or closing the connection**, unlike both timeout paths beside it. A stale
queued response is then handed to the next command, offsetting every read after
it. It did not fire in any of these runs; it is a hazard on its own merits.

⚠️ **This displaced G6 as the recommendation on 2026-08-24, and handed
it on to G3 on 2026-08-25 when the fix merged** — see the table above. The
reasoning while it stood, kept because it is the standing tie-breaker: release
sequencing will keep, and a cross-atSign read that silently returns the wrong
record was the sharpest thing open anywhere in the tree.


### G2 — build the acceptance suite out

**G2. ✅ DISCHARGED 2026-08-24 — build the acceptance suite out per [ruling 115](decisions.md#115-the-acceptance-suite-is-4-arms-and-a-ledger-not-one-grid-2026-08-23).** Arms 1–3, the ledger and its clause level are all built; arm 4 is cancelled. Nothing here is startable — the entry is kept because it carries the design and the measurements, and because a reader who deletes it re-derives ruling 115 from scratch.
The gate that D1's own definition rests on, and the largest. gkc's framing:
hundreds of functional and e2e tests cover the acceptance set between them, and
there is no definitive place to see the whole of it being proven; the posture
matrix is the logical place to build that out. **The gap is now established and
the design is ruled** — the first two of this entry's three owed steps are
discharged, and what remains is the build. **Of that build, four pieces have
landed (2026-08-23) and are named here so they can be grepped rather than
re-derived:** the ledger (`packages/at_client/tool/acceptance_ledger.dart`),
its local driver (**`tools/acceptance_ledger.sh`**, `--with-live` for the live
packs), its wiring rail
(**`packages/at_client/test/acceptance_ledger_wiring_test.dart`**) and **arm 1**
(**`tests/at_functional_test/test/pq_stage_arm_test.dart`**). ⚠️ **This read
"Arms 2–4 and the ledger's clause level have not [landed]"**, and then "what
remains of this entry is the ledger's clause level alone" — on 2026-08-24 arms
2 and 3 were built, arm 4 was cancelled, and the clause level was built, so
**nothing in this entry is owed**. Read the ✅ markers below before starting
anything here.

✅ **Arm 1 is BUILT (2026-08-23) — do not build it again.** This paragraph
opened "Start here, and it is startable now: build **arm 1**, the 3-cell stage
arm, in `tests/at_functional_test`", and that is done:
`test/pq_stage_arm_test.dart`, **186/186** in the full pack *as it then was* — ⚠️ the pack is **183** now (181 pass, 2 skipped), the two skips being the G0 harnesses; do not read 186 as current, with
**UC-C1.2 executed for the first time** — `disallowLegacyEncryption` has no
setter and no constructor argument, so a posture is the only way to reach it,
and it had 0 hits under `tests/`. Three things a reader should not re-derive.
**The arm is 3 enrollments, not 3 clients**: `AtClientImpl` keys its cache by
`(atSign, enrollmentId)` and `refuseChangedRolloutAxes` throws when a second
client asks for the same key under different rollout axes, so three postures
need three cache keys. **The refusal is at `crypto_runtime.dart:156`**, not at
`at_client_impl.dart:753` as this section said — that line is
`_announceLegacyEncryptionPosture`, which logs. And **the arm covers the rows
both derivations agree on**, not the contested 21
([which](../acceptance.md#which-rows-arm-1-owes)); it does not measure UC-C1.4,
because `enrolAndAuthenticate` builds pq-mode enrollments only and every cell
therefore holds `keyExchangeMode` constant.
✅ **Its one real prerequisite is now built**
(2026-08-23): this entry read that the pack "has no `dart_test.yaml` and no
`pq` tag", and it now declares the tag with **34** of the 55 test files it weighs
carrying it (⚠️ this recorded **29 of 49**, the count on the day it landed),
guarded by `test/pq_tag_test.dart` — a rail that re-derives the set from the
mechanisms a file drives, so a new PQ test cannot sit outside it unnoticed.
⛔ No `paths:` allowlist, deliberately: this pack's virtualenv is thrown away
per run, so allowlisting would carry the e2e pack's silent-omission risk with
none of its benefit. ✅ The prerequisite that read "`PqPosture.pqActive` breaks the monitor"
is **measured away** — see the correction below and in
[14.34](#1434-an-unexplained-intermittent-in-self_enrollment_retrofit_live_testdart).
✅ **The ledger, this entry's second piece, is BUILT** (2026-08-23), so do not
build it again. This paragraph said it "needs `manifest.dart` moved from
`packages/at_client/test/` to `lib/` before any pack can import it" — it did
not, and the move was never made: the test runner's own
`--file-reporter json:` output plus the citations `provenIn` records are
sufficient, so nothing was moved into at_client's shipped surface and none of
the 194 live tests changed. `packages/at_client/tool/acceptance_ledger.dart`
renders it, `test/acceptance_ledger_test.dart` guards the join, and four CI
jobs upload the inputs. Rendered from a real CI run's artefacts across both
workflows it reads **63 PROVEN · 0 NOT-EXERCISED · 6 NO-LIVE-CITATION** across
69 rows (2026-08-23). ⚠️ This said "over all four report sources … 62 PROVEN ·
1 NOT-EXERCISED", which was a LOCAL render; UC-B0.1 is the differing row and
only CI exercises it. Re-derive with `tools/acceptance_ledger.sh`. The full description is in
[acceptance.md section 14](../acceptance.md#14-test-harness--implverify-mapping).
⚠️ `manifest.dart` is still where it was, and that still blocks the *in-pack
rails* idea — a different thing, wanting each pack to assert its own citations
— so the prerequisite stands for that reason and not for this one.

✅ **Arms 2 and 3 are BUILT (2026-08-24) — do not build them again.** Arm 2 is
`tests/at_functional_test/test/pq_posture_grid_test.dart` (**7** `test()` calls)
and arm 3 is `tests/at_functional_test/test/pq_advance_ladder_test.dart` (**1**,
phased). ⚠️ **This paragraph read "So what remains of this entry is arms 2 and
3, plus the clause level of the ledger"**, and before that "arms 2–4 … arms 3
and 4 need the EE at a named `at_server` ref". Both halves of the older claim
changed on 2026-08-24: **arm 4 is cancelled** by gkc (the hosted fleet will run
the version a release requires), and **neither arm 2 nor arm 3 needed the EE**
— the belief that a transition could not run in the VE generalised the matrix's
rule against re-minting in a *cell* to an advance, and 24 retrofits across five
live runs on one virtualenv refuted it. ✅ **The clause level is BUILT too (2026-08-24)**, so this entry owes nothing.
⚠️ **This read "So what remains of this entry is the ledger's clause level
alone."** `provenIn` takes `clauses:` — distinctive fragments, each of which
must resolve to exactly one THEN clause of its row — and
`tool/acceptance_ledger.dart` renders a per-row checklist plus a catalogue
total. First render: **129 clauses across 68 live rows**, 7 pinned by a proven
citation, UC-A2.4 at **5 of 6**. ⛔ It did NOT need `manifest.dart` moved to
`lib/`, which both this plan and ruling 115 gave as its prerequisite: the tool
imports `../test/acceptance/manifest.dart`, so one parser serves the tool,
`provenIn` and the docs rail.

**The design was ruled with gkc on 2026-08-24 and is written up in
[acceptance.md section 14](../acceptance.md#the-arms), with the provisioning in
[how the postures are provisioned](../acceptance.md#how-the-postures-are-provisioned).**
Do not re-derive it from ruling 115, which is amended rather than rewritten.
In short:

1. **Arm 2 replaced the 4×4** with one in-process grid over sender posture ×
   receiver **readiness** — self and cross-atSign puts, gets and notifications,
   with per-cell expected outcomes, carrying the signed-envelope exchange
   (which stays posture × posture) too. ⚠️ This read "receiver posture" for
   both grids; the data-path axis became readiness on 2026-08-24, for the
   reason in [how the postures are
   provisioned](../acceptance.md#how-the-postures-are-provisioned).
2. **Arm 3 is a separate ladder**, legacy → pqReady → pqActive on one
   enrollment, asserting the `.atKeys` shape per rung and re-reading
   pre-advance data. Both rungs evict `AtClientImpl.atClientInstanceMap`
   first.
3. **`tests/pq_matrix/` was cut to the released peer** — the scenario package,
   both programme arms and the `##PQM##` line protocol are gone, and
   `tests/at_functional_test/test/pq_released_peer_test.dart` keeps UC-G1.14
   proven. ⚠️ This read "`tests/pq_matrix/` **is deleted**", and the directory
   is still tracked: the released-peer test spawns
   `tests/pq_matrix/published/bin/read_apsk.dart`, which imports
   `published/lib/arm.dart`, so `published/` and `scenario/` survive and
   `current/` is what went. Re-derive with `git ls-files tests/pq_matrix`.
4. **Provisioning is 2 atSigns × 9 enrollments across 2 namespaces**, live
   proven 2026-08-24, each cell holding its own Hive store and its own
   `InMemoryAtKeysIo` — without the latter a minted nskey private is filed
   nowhere and every reader fails. ⚠️ This read "**7** enrollments across **5**
   namespaces", which was the design before the receiver axis became readiness.
   Re-derive from `cellSpec` in the arm: 4 sender postures + a second pqActive
   sender + 3 receiver postures + an unready receiver.

⚠️ **The grid discharges far less of the catalogue than "a structured suite over
the acceptance set" suggests, and that was measured rather than assumed.**
Classifying all 69 rows against these arms gives **0 fully covered, 32 partial,
34 reached by no arm, 2 out of scope, 1 needing a released peer**. The reason is
structural: the arms assert *outcomes*, while a large share of clauses assert
record shapes, orderings, negatives, and that an artefact signed earlier still
verifies. Nearly every unreached row is already proven live elsewhere. Treat the
grid as the legible core, not as a replacement for the packs.

The measurement, 2026-08-23: 59 of 68 rows have live proof and 9 have none, so
coverage was never the gap; 135 `provenIn` citations split **68 live / 67
unit**; and of the 68 rows only **3** are shaped like a grid cell while **38**
do not vary by posture at all. Ruling 115 carries the full table, the design
(**4 arms and a generated ledger**, not a bigger grid) and the 4 verified
prerequisites.

⚠️ **This entry read "Measured 2026-08-23: 180 live test declarations across 65
files … a looser one gives 225", and both figures were scoped to 2 of the 4
live packs.** `tests/at_onboarding_cli_functional_tests` and
`tests/at_onboarding_cli_functional_tests_proxy` are live packs too, no
citation reaches either, and the CLI one builds clients from a `PqPosture` in
two arms. Across all 4 the strict matcher gives **194** and a multi-line-aware
one **247** — and that gap is entirely declarations whose name sits on the next
line, since an any-position same-line matcher also gives 194:

```bash
grep -rhoE "^[[:space:]]*test\([[:space:]]*'" tests/ --include='*.dart' | wc -l   # 194
perl -0777 -ne 'while (/(?<![A-Za-z0-9_])test\(\s*[\x27"]/gs){$n++} END{print "$n\n"}' \
  $(find tests -name '*.dart')                                                    # 247
```

The "29 of the 69 ids nameable" figure stands, and is a citation count rather
than a coverage count. ⚠️ It also read "the matrix is still 3 `test()` calls
proving 2 use cases" — the rollout matrix was **deleted** on 2026-08-24 and its
two rows rehomed: UC-G1.15 onto `pq_posture_grid_test.dart`, UC-G1.14 onto
`pq_released_peer_test.dart`.


### G3 — the self-retrofit monitor race

**G3. ~~[RECOMMENDED]~~ Diagnose [14.34](#1434-an-unexplained-intermittent-in-self_enrollment_retrofit_live_testdart).**
⚠️ **The marker is struck, not deleted: it belonged to G4 from 2026-08-25 and this heading kept it, so the one ranked list carried TWO recommendations.** The startability table above is the authority — it puts `[RECOMMENDED]` on G4 and lists G3 under "discharged". Struck rather than removed because the prose below cites the marker's movement.
A live-pack failure at once in five, unexplained. A gate only because D1 now
ends when every rail is green, and at that rate "green" is a rate rather than a
state.

✅ **DISCHARGED 2026-08-25 — diagnosed, ruled, fixed and pack-proven, with the
far-side log this time captured.** ⚠️ This read "DIAGNOSED", and the table above
carried "what is left is one full functional pack run carrying the change"; the
pack has since run twice at **183 pass, 2 skipped**, exit 0, carrying it. ⚠️ This
entry read *"Start by RE-MEASURING the rate, not by diagnosing"*; the rate turned
out to be the wrong instrument and the diagnosis came from the margin instead —
see below. ⚠️ **This sentence read "What is now owed is a decision about the fix,
not an investigation" for a day after gkc had made that decision and the fix had
shipped** — seventy lines above this entry's own ✅ RULED paragraph, and beside a
`## TODO` row still calling the intermittent "Unexplained. Not a flake and not
fixed". **Nothing is owed here.** The ruling, the build and the live proof are
all below.

**What happens.** The atServer receives the test's ping *before* it has processed
the retrofitted client's `monitor:`, so at that instant nothing is subscribed and
the notification is written to **no connection at all**. Captured on the atServer's
own log, one failing run, times are the atServer's:

| | |
| --- | --- |
| `RCVD: notify:…rf2cmon-618149102…` | `09:42:08.207762` |
| `NotificationManager enqueue …rf2cmon-618149102…` | `09:42:08.208185` |
| `RCVD: monitor:selfNotifications` (the retrofit client) | `09:42:08.210581` |
| `SENT: notification:` for that id | **never, to any connection** |

The client had written `monitor:` 6.9 ms earlier (`AtLookup|SENDING: monitor:
selfNotifications` at `10:42:08.203687` local, `Monitor|monitor started` 248 µs
after) — so the inversion is in how long the atServer took to *read* the command
on a socket it had just PKAM-authenticated, not in what order the client sent.

**Why the test's guard cannot close it, and why no guard could.** Three facts,
each read in source rather than inferred:

- `AtLookupImpl._openNotificationStream` emits `notificationConnectionUp = true`
  — which is what becomes `NotificationListenerState.listening` — immediately
  after `await _connection!.write(command)`. It means *"we wrote `monitor:`"*,
  never *"the atServer is delivering to us"*.
- `MonitorVerbHandler.processVerb` subscribes the connection to the atServer's
  notification broadcast stream only when it *processes* that command.
- ⛔ **The `monitor:` verb is unacknowledged by design**: at_server's
  `MonitorResponseHandler.getResponseMessage` returns `''`, so the atServer writes
  **zero bytes** back. There is no signal on that socket a client could wait for.

And nothing recovers the gap: a first-ever monitor sends `monitor:selfNotifications`
with no watermark, and only `monitor:…:<epochMillis>` replays from the store. A
long-lived client is exposed on its **first** subscribe only; this test builds a
brand-new client every run, so it is exposed every run.

**The margin is the instrument; the pass/fail outcome is not.** Measured
2026-08-25 against `at_virtual_env:g0fixed`, as microseconds between the atServer
receiving `monitor:` and receiving the ping (positive = the monitor got there
first). Two arms differing in one thing — an environment-driven pause inserted
between the client calling itself `listening` and the ping going out:

| arm | n | margin, µs |
| --- | -: | --- |
| no pause (the shipped behaviour) | 10 | **−2819**, +92, +114, +121, +225, +859, +975, +1063, +1155, +3472 |
| 500 ms pause | 6 | +503734, +504348, +505349, +506870, +509759, +510254 |

One negative value, and it is the failing run. A distribution straddling zero is
the finding — not the failure count.

⛔ **Do not use the pass/fail rate to decide anything here.** The identical
unpaused arm gave **4 failures of 10** and then **0 of 10** within one hour, same
image, same virtualenv, same test bytes. That is the same shape as G0's ordering
confounder and it has already produced two wrong conclusions on this row. The
margin yields a number from every run, including the ones that pass.

**To reproduce**: bring the virtualenv up on a named image and leave it up
(`docker compose up -d` in `tests/at_functional_test/test` with `VIRTUALENV_IMAGE`
set, then the pkamLoad wait out of that pack's `runLocal.sh`), run
`dart test test/self_enrollment_retrofit_live_test.dart --concurrency=1` in a
loop, and **copy `/apps/logs` out before any compose-down**
(`docker cp test-virtualenv-1:/apps/logs <dir>`). ⚠️ The atServer logs at FINEST
here and **rotates at ~52 MB**, so `alice🛠.log` alone covers only the last few
seconds of a 20-run block — read `alice🛠.log.*` too, or a grep returns a
confident zero. Pair each notification with the `monitor:` nearest it in time and
subtract.

✅ **RULED by gkc 2026-08-25, after the shape below was measured: fix the
CALLER and the test, not the protocol.** The window is real but it is largely
self-healing in production — `getLastNotificationTime()` seeds the watermark to
`DateTime.now()` on its first call and returns null, so the *next* monitor
reconnect asks the atServer to replay from just before the window and the
missed notification arrives then. ⚠️ That seed is a **client** clock compared
against the atServer's own notification timestamps, so a client running ahead
of its atServer skips the replay and the notification is gone; "delayed rather
than lost" is conditional on clock agreement, not on the race.

**What that ruling produced, and it is not confined to the test:**

⛔ **`AtRpc` was exposed and undefended, which is what turned the ruling.**
`AtRpc.start()` subscribes for response notifications and returns — it does not
even wait for `listening`, so it is *more* exposed than the test was. The caller
then sends a request, and the far side answers with a notification back over
that same listener. Measured across 94 monitor starts in this session, the gap
between `subscribe()` returning and `monitor:` reaching the socket ran **19 ms
to 383 ms, median 152** — long enough for a fast round trip to beat it, and the
microsecond figures below are only the *residual* after a `listening` wait.
`sendRequest`'s retry loop does not cover it: it sets `sent = true` as soon as
the notify succeeds and retries only on an exception. `AtRpcClient.call()` is
the sharp end — it returns a future completed only by the response, with **no
timeout**, so a lost response hangs the caller for good.

**Built 2026-08-25:** `AtRpc.ready()` and `AtRpc.listenerReadyTimeout`, with
`sendRequest` awaiting readiness when `isClient`; and the ping in
`self_enrollment_retrofit_live_test.dart` retried until one lands rather than
sent once. Rails: `packages/at_client/test/rpc/at_rpc_readiness_test.dart`
(4 tests, four mutations each reddening its own assertion — the wait deleted,
the current-state read deleted, the `isClient` guard removed, and the timeout
swallowed), at_client unit **1550** and at_policy **5** at exit 0, at_client
`dart analyze lib test` exit 0 / 422 info and the format gate exit 0,
`tests/at_functional_test` analyze exit 0 / 246 info.

**Live, against `at_virtual_env:g0fixed`, and the fix is observed rescuing
NATURAL instances rather than only forced ones.** Twenty runs of the shipped
shape, counted from the atServer's own log by pairing each ping key with the
`notify:` commands carrying it — a key received twice is a run whose retry
branch fired:

| | |
| --- | --- |
| runs | 20 |
| runs where the retry fired | **4** |
| runs where the notification reached no connection | **0** |

Against **4 of 11 never delivered** on the same harness before the fix. Four
retries in twenty is a rate consistent with the 4-of-10 measured pre-fix, so the
failure is still occurring and is being recovered.

⚠️ **Count the pings from the atServer's log, never the client's.** The client
log prints the notification key only on success, so a client-side `grep -c` read
`1` for all twenty runs including the four that retried — it would have reported
"the retry never fired" for entirely the wrong reason.

An earlier block of **8 of 8 green** proved nothing: one ping each, so the window
fell the right way every time and the retry was never exercised. The retry was
first proven by forcing the window open — skipping the client's `listening`
wait, which puts the ping inside it every time — and varying only whether the
ping is retried: **retry off, 3 of 3 failed** with `TimeoutException` on the
awaited notification; **retry on, 2 of 3 passed**. ⚠️ The third was red for an unrelated reason — a keyfile lock
contention (`Could not acquire the keyfile lock`) on `rf2b-t5@alice🛠.atKeys`
inside `mintLegacyKeyfile`. That is **one sighting** under an artificial
configuration, absent from 30 pre-change runs and from 8 post-change shipped
runs; it is a sighting, not a rate, and it is not attributed to anything.

⚠️ **What is NOT owed: the protocol change.** The four candidates were weighed
and gkc chose the caller-side fix. The protocol option is real and is already
specified upstream — see the `monitor:` acknowledgement row in
[`## TODO`](../implementation-plan.md#todo), which also carries a correction to that specification that
must be settled before anyone builds it.

The four candidates, kept because the ruling is only legible against them:

1. **Fix the test only** — have it prove registration before it pings (send a
   warm-up notification and wait for it, or retry the ping). Closes this gate;
   leaves every app with the same window on its first subscribe.
2. **Acknowledge `monitor:`** — the atServer returns a line once it has
   subscribed, and at_lookup holds `up` until it arrives. Closes it for everyone,
   and it is a protocol seam: at_server plus at_lookup in one sweep, with a
   timeout fallback so an older atServer that answers nothing does not hang a
   client (which reopens the window against old servers, knowingly).
3. **Send a watermark when there is none** — ⚠️ the epoch is compared against the
   atServer's own notification timestamps, so a client-local `DateTime.now()`
   makes delivery depend on clock agreement between two machines. A
   server-supplied value would fix that, and **there is none to hand on the
   monitor connection**: the `from:` challenge on the self path is a bare
   `Uuid().v4()` with no timestamp in it (read in at_server's
   `FromVerbHandler`, trunk, 2026-08-25). So this option costs a new
   server-clock source before it costs anything else.
4. **Do nothing and say so in the API** — document that `listening` means the
   command was written, and that a first subscribe has no delivery guarantee.

⛔ Read [14.34](#1434-an-unexplained-intermittent-in-self_enrollment_retrofit_live_testdart)
and [14.43](implementation-plan.md#1443-the-functional-suites-convergence-race)
together before acting: they were written months apart without noticing each
other, and the instruction to work them together is the part that keeps getting
lost.


### G4 — migrate 14.11's bucket B

**G4. Migrate 14.11's bucket B** — the 71 credential-ladder uses
(`enrollmentId` 59, `signingAlgoType` 12) onto the `AtAuthenticator` seam that
at_lookup 3.7.0-rc1 ships. ⚠️ **This read "ships **on trunk** — pub.dev is
still 3.6.1, and in this file that distinction is the whole gate", and it was
wrong**: `3.7.0-rc1` has been on pub.dev since 2026-08-23. pub.dev's `latest`
field excludes prereleases, which is the trap this file names at the top and
then fell into here. So the distinction G4 called its whole gate does not
exist, and nothing external blocks this entry. The only one of the five
`deprecated_member_use` buckets with a replacement that exists today.

⚠️ **RE-MEASURED 2026-08-25 and the scope was wrong in two ways.** This read
"**24** sites in `lib/`, **47** in tests, across at_client, at_onboarding_cli
and at_auth", from `enrollmentId` **59** and `signingAlgoType` **12**. Measured
after the at_auth merge:

| package | `lib/` | `test/` | files |
| ------- | -----: | ------: | ----- |
| at_client | 15 | 32 | 10 + 17 |
| at_onboarding_cli | 8 | 17 | 1 + 3 |
| at_client_flutter | 0 | 10 | 3 |
| at_auth | 3 | 0 | 2 |
| **total** | **26** | **59** | **85 sites in 36 files** |

⛔ **`at_client_flutter` is in scope and was not named** — 10 sites in
`keychain_io_impl_test.dart` (8), `keychain_storage_test.dart` and
`test/data/keychain_data.dart`. That is a whole package missing from the stated
scope, not a stale count.

**Use the ANALYZER, never a grep.** `enrollmentId` is a legitimate identifier in
hundreds of places; only the analyzer knows which uses are of the deprecated
member. Re-derive per package with
`dart analyze lib test | grep deprecated_member_use | grep -c "'enrollmentId'"`,
and the same for `'signingAlgoType'`.

**Where the work concentrates**, which is what makes it a list rather than a
sweep: `at_onboarding_cli/lib/src/onboard/at_onboarding_service_impl.dart` holds
**all 8** of that package's library sites;
`at_client/lib/src/client/remote_secondary.dart` holds 5 of at_client's 15; and
on the test side `at_client_flutter/test/keychain_io_impl_test.dart` (8) and
`at_client/test/signing_algo_threading_test.dart` (7) are the two largest. Four
files carry 28 of the 85.


### G5 — close 14.19 item 36

**G5. ✅ DISCHARGED 2026-08-24 — close 14.19 item 36.** All three clauses are
live-proven in `tests/at_functional_test/test/key_package_amendment_live_test.dart`
and pinned from `a2_enrollment_test.dart`, so the ledger counts them. ⚠️ This
read "**The work is still owed** — computing a gap is not closing it", and
before that "three clauses … it was found by hand".

**Two of the three changed what the catalogue says, and that is the part worth
reading before trusting the row:**

- **A2.6's "state gate" is not a check inside `enroll:update`.** There is none.
  The outcome holds because a revoked enrollment can no longer authenticate at
  all (`AT0027 … is revoked`) *and* every other connection, the fully
  privileged owner included, is refused as not-self (`AT0011 … enroll:update is
  self-only`). ⚠️ **One arm is still unproven**: an enrollment revoked while it
  holds an already open, already authenticated connection — the live arm
  reconnects, so it measures the post-revocation handshake.
- **A2.5's envelope clause said "superseded", and nothing is superseded here.**
  An amendment **joins** a key; the original stays `active`, which the test now
  asserts. Supersession is rotation's shape.
- The negotiation clause's axis is **`AtClientPreference.sealsToKeyAlgorithms`**
  — what a sender picks among the keys a recipient offers — not
  `keyEstablishmentAlgorithms`, which is what an atSign mints. A test varying
  the second observes nothing.

Each arm is mutation-proven: same sender order collapses the negotiation
differential, sealing nothing beforehand reddens the carry test's precondition,
and skipping the revoke makes the refused request succeed.


### G6 — the train

**G6. The train** — ⚠️ this read `[RECOMMENDED]` and was the head of the list
until G0 displaced it on 2026-08-24. It is still the next *release* step, and its
next step is unblocked and nothing else's is. ⚠️ This read "Merge #2179 →
**gkc publishes at_lookup 3.7.0-rc1** → gkc publishes at_auth"; at_lookup
3.7.0-rc1 and at_server_status 1.1.2-rc1 were both published by 2026-08-24, so
that middle step is done.

**What to do, in order: gkc publishes at_auth 4.0.0-rc1**, then carve at_client
→ at_client_flutter → at_onboarding_cli. ⚠️ This step read "merge
[#2179](https://github.com/atsign-foundation/at_client_sdk/pull/2179) — OPEN,
MERGEABLE, CI green on 2026-08-24 — then gkc publishes"; **#2179 merged to
trunk on 2026-08-25** as `09fc94d28`, so six of the eight train positions are
through by merge and the publish is what is left. at_auth 4.0.0-rc1 is **not on
pub.dev** — checked against the versions list, which is the only form that can
see a candidate.

✅ **The at_commons floor is FIXED.** This paragraph said "before carving
at_client, raise its `at_commons` floor: it declares `^5.15.0`", and it now
declares `^5.16.0` — raised 2026-08-25 after checking the published packages
themselves rather than the changelog: `Metadata.copy()` is absent from
at_commons 5.15.0 and present in 5.16.0. ⚠️ **That was one floor, not a sweep.**
Every other floor at_client declares is still unchecked against first use.


### G7 — step 20's rotation arm

**G7. Step 20's rotation arm** — publish at_auth, add the `pending` status
value, build the arm against its own dedicated CRAM atSign. ⛔ There is **no**
fleet-adoption wait: see the standing premise above.


### G8 — a write that skips the commit log

**G8. ✅ BUILT 2026-08-25 — the short-lived lock records no longer grow the
commit log.** Asked for by gkc the same day. ⚠️ **Whether it ever gated D1 is
his call and he never said** — it was recorded because he asked for it next, not
because it was a gate. Nothing here is startable; the entry stays because it
carries the two traps and the compatibility finding, which apply to any later
caller reaching for the same flag.

**What landed.** `noCommit` on `PutRequestOptions` and `DeleteRequestOptions`,
both off by default, propagated into the update and delete verb builders, and
set on the lock write in `MintLock` — which is the one path both lock records
take. Rails: `packages/at_client/test/no_commit_test.dart` (6 tests, four
mutations each reddening its own assertion, including the symmetric one that
sets the flag always), at_client unit **1556** exit 0, analyze exit 0 / 422 info,
the format gate exit 0, and the functional pack **183 pass, 2 skipped** exit 0.

✅ **The atServer's behaviour is measured, not assumed.**
`tests/at_functional_test/test/no_commit_live_test.dart` runs two arms with the
control first: an ordinary write moves the atServer's latest commit id, and a
write asking not to be recorded leaves it where it was. Mutating the put path to
drop the flag makes the second arm read a delta of 1 and fail, so the test
discriminates rather than being green for free.

⚠️ **Two corrections to what this entry first said, both about compatibility,
and the second is the one that matters.**

- It said an older atServer *"does not match the command at all — the operation
  is refused as invalid syntax"*. **Wrong, and backwards.** `:nc` has been in
  the shared verb syntax since at_commons **5.10.0**, far longer than any
  atServer has acted on it, so an older atServer parses the flag, **ignores it,
  and records the commit anyway** — nothing refused, no error returned, and a
  caller cannot tell. It is an optimisation that may not happen, never a
  guarantee that a record stayed out of the commit log.
- The flag does more than skip. The atServer honouring it also **purges any
  commit entry the key already has**, and answers `-1` where it would otherwise
  return a commit id. at_client tolerates that on both paths — delete only tests
  for non-null, and put hands the response to its transformer — but a future
  caller reading the response as a commit id would be surprised.

⛔ **The interlock is unaffected, and that was checked rather than assumed**: the
atServer refuses a second write to an immutable record in its pre-processing,
before the write the flag modifies, so the refusal that *is* the lock still
happens.

⚠️ **A third fault, found by gkc asking what breaks on the `-1`: the option was
a silent no-op on the default routing.** `PutRequestOptions.useRemoteAtServer`
defaults to `false`, and `getRemoteLocalPrefForOp(false, …)` returns
`localOnly` **unconditionally** — the preference is not even consulted. The
local secondary has no notion of the flag, so the record took a local commit
entry and sync pushed it later under a hand-built command carrying none: the
commit happened anyway and nothing said so. **Now refused, naming the fix**, at
the top of the put before any encryption or storage work — the old position was
never even reached on a client with no local store. The routing decision is
extracted so the refusal and the write cannot disagree. Three more tests, three
more mutations; at_client unit **1559**, functional pack **183 pass, 2 skipped**.

**And the `-1` question itself, answered narrowly:** one place would misread it.
`sync_service_impl.dart`'s batch-push response handler does
`commitId = int.parse(responseObject.data!)` and then treats `-1` as *the
operation having failed*, logging `severe`. It is unreachable today because sync
builds its own commands and none carries the flag. Everything else tolerates it:
the response is carried as a **String**, `put` returns `response.isNotEmpty`,
`delete` returns `result != null`, the other two `int.parse` sites read a stored
watermark rather than a write response, and `MintLock` discards the response.

The original entry follows, because the two traps in it are what a later caller
needs.

at_client writes several records to the remote atServer that should drive no
commit-log entry at all. The immutable "lock" records are the clear case: every
one of them carries a small time-to-live so it expires quickly, and each still
costs a permanent commit-log entry that every other client of that atSign then
syncs. The atServer already has the feature — the `update:` and `delete:` verbs
take a flag meaning "do this without recording a commit" — and at_client is the
only tier that has not been given a way to ask for it.

**Everything below was checked in source on 2026-08-25 rather than taken on
trust, because the whole item rests on the feature already existing:**

- **The atServer implements it, on its trunk.** `update_verb_handler.dart`,
  `update_meta_verb_handler.dart` and `delete_verb_handler.dart` each pass
  `skipCommit: verbParams[WireParams.noCommit] != null`. It is in the canary
  release, and therefore in the `dev_env` image CI uses and in the local
  virtualenv build.
- **at_commons carries it.** `UpdateVerbBuilder.noCommit` and
  `DeleteVerbBuilder.noCommit` emit `:nc`, and the verb syntax parses
  `(:nc(?<noCommit>))?` at three sites. ✅ **It is in the PUBLISHED at_commons
  5.16.0**, which at_client already floors at, so this needs no version change
  and no publish.
- **at_client has none of it**: zero occurrences of `noCommit` anywhere in
  `packages/at_client/lib`.

**The commit entry costs more than log growth, and the code already says so.**
`local_secondary.dart`'s expiry sweep carries this, written for a different
reason: `_nskeylock` records are *"created remote-only by MintLock, synced down
like any other key, and released by ttl alone"*. So each lock is replicated into
every client's local store, expires there, and then needs a special
`isExpiry: true` delete to be reclaimed at all — because a client whose
enrollment does not cover the record's namespace *"can never reclaim it"*
otherwise. A write that drives no commit entry is never synced down, so none of
that happens.

**Both lock records go through one call site.** There are two —
`_nskeylock.<ns>@<owner>` and `_rootlock@<atSign>` — and `MintLock` takes both
by the same path, so `mint_lock.dart:139` covers them together.

**What to build:**

1. `noCommit` on **`PutRequestOptions`** and **`DeleteRequestOptions`**
   (`packages/at_client/lib/src/client/request_options.dart`), defaulting off.
2. Propagation from each into `UpdateVerbBuilder` / `DeleteVerbBuilder`.
3. The lock writers themselves set it.

**Where the two options land**: `put_request_transformer.dart:33` builds the
put path's `UpdateVerbBuilder`, and `at_client_impl.dart:1118` builds delete's.
Fifteen sites in `lib/` construct one of the two builders; the rest are durable
records — shared keys, the published key ring, the signing root — which must
keep committing.

⚠️ **Step 1 alone does not reach the records that motivated this, and it looks
as though it would.** The lock writers do not call `put()`:
`packages/at_client/lib/src/crypto/nskey/mint_lock.dart:139` goes straight to
`atClient.getRemoteSecondary()!.executeVerb(UpdateVerbBuilder() …)`. Those call
sites set the builder field directly, so find them by grepping for the builders
rather than by following the options classes.

⛔ **Three hand-built command strings must NOT get the flag**, and a sweep that
threads it everywhere will reach them: `sync_service_impl.dart` builds
`'delete:$atKey'`, `'update:$atKey …'` and `'update:meta:$keyWithMeta'` as
strings. That is sync replaying this client's local changes onto the remote —
suppressing the commit entry there is precisely how another client stops seeing
the change.

**How to test it, and the trap.** A round-trip test on the options class is
green for a field nothing sends: what reaches the atServer is whatever the
*builder* copies into the command. Pin the built command as a raw literal, with
the flag and without, and add a live arm that writes a lock and asserts the
atServer's commit log did not grow — which is the behaviour, and the only thing
that distinguishes the feature working from the flag being silently dropped.


### G1 and the blocked note, as they stood

**POST-D1 CLEAN-UP. Not gates, and not to be worked before D1 closes.**

⛔ **G1 was a D1 gate until 2026-08-23 and is now post-D1 clean-up** (gkc).
It keeps its letter rather than being renumbered, because prose above and
below cites these letters and a shift would silently repoint every one of
them. So the D1 gates are **G0 and G2–G7**, and G1 sits here. ⚠️ This read
"**G2–G7**" until 2026-08-25 — the same falsified sentence that the note under
[`## THE NEXT MOVE`](#15-the-lettered-d1-gates-g0g8-as-they-were-discharged) had already corrected in its own copy, left
standing here because a claim with two homes only ever gets fixed in the one you
have open.

**G1. Test the registrar's certificate validation.** ⚠️ **This said "on
[PR #2179](https://github.com/atsign-foundation/at_client_sdk/pull/2179) while
it is still open", and that home is gone** — #2179 merged on 2026-08-25. The
work is unchanged and now lands wherever at_auth is next touched, or on the
spike branch. The last S-5 behaviour change that exercises nothing, and
the only one with a security consequence: the default client used to accept any
TLS certificate on calls carrying the registrar API key. Neither arm has a test
and CI is blind — `RegistrarIoClient` appears in zero job logs. The harness is
settled and written up in its `## TODO` row: mint a self-signed cert in
`setUpAll` with `openssl` (**do not commit a PEM** — push protection blocks
private keys), serve it with `HttpServer.bindSecure`, point `RegistrarService`
at `localhost:<port>`, and run three arms — default refuses, io client with the
flag off refuses, io client with the flag on succeeds. The third is the
positive control without which a refusal is indistinguishable from a server
that never started. ⚠️ A probe got one import short on 2026-08-23: it needs
`import 'package:at_auth/at_auth.dart';`, which is what exports
`RegistrarApiEndpoint`.

**Blocked, and what lifts it:** ~~publishing anything past at_chops waits on
at_chops 3.6.0 reaching pub.dev; at_lookup's publish additionally waits on
at_commons 5.16.0~~ — both published 2026-08-21. ⚠️ **That did NOT leave the
train unblocked, and this paragraph said it had until 2026-08-22.**
[14.49.2](implementation-plan.md#14492-every-remaining-package-publishes-as-a-release-candidate)
moved every remaining package to a candidate the same week, so the live gate is
now **at_auth `4.0.0-rc1`, which is not on pub.dev**. ⚠️ This named at_lookup
`3.7.0-rc1` and said it was unpublished; it was published by 2026-08-24, and the
command below was reading `latest`, which never shows a prerelease. Re-derive
with
`curl -s https://pub.dev/api/packages/at_lookup | python3 -c "import sys,json;print([v['version'] for v in json.load(sys.stdin)['versions']][-5:])"`).
⛔ **at_auth floors `^3.7.0-rc1`, and that did NOT block its carve — this
sentence said it did until 2026-08-23.** A pub workspace resolves its siblings
by path, so [PR #2179](https://github.com/atsign-foundation/at_client_sdk/pull/2179)
resolved, went 47/47 green with at_lookup unpublished, and **merged on
2026-08-25**. What the publish gates is **publishing at_auth**, never carving or
merging it — which the merge has now demonstrated rather than merely asserted. Each package still waits on its own predecessor being released before it
can declare a floor against it, which is what the order in
[14.18](../implementation-plan.md#1418-the-remaining-d1-initial-development-sequence) is for.
The remaining external gate is the one 14.18 records for the LAST carves, not
the next: the spike's test packs need a VE image that verifies ML-DSA PKAM,
settled by moving CI to `dev_env`.

### The branch's CI history, and how it misled three times

⚠️ **CI on this branch cannot catch up by itself.** Nothing fires on push
here — the workflow is `workflow_dispatch` only on this branch — so the newest
run is as new as the last manual dispatch and no newer.

⛔ **CI HAS NOT COVERED THE CURRENT CODE, and this paragraph claimed it had.**
The last CI-verified commit is **`64480808d`** — runs **`32588333812`**
(at_client_sdk, 11/11) and **`32588342275`** (at_libraries, 13/13), both
`success`, measured 2026-08-22. Since then, re-derived 2026-08-24:

```bash
# Both figures GROW with every commit, so they are stamped with the head they
# were measured at rather than a date — an unstamped answer beside its own
# command reads as current forever. Re-run; do not quote.
git rev-list --count 64480808d..HEAD                              # 53 at 52ad01a59
git diff --name-only 64480808d..HEAD | grep -vc '^docs/'          # 108 at 52ad01a59
```

⚠️ **This paragraph read "THE BRANCH IS GREEN, at the current tip … HEAD is 8
commits past it and `git diff --name-only 64480808d..HEAD` is entirely under
`docs/`, so this green still covers every line of code on the branch."** Both
figures were wrong when written, not merely overtaken: the acceptance-ledger
commits of 2026-08-23 had already touched `tool/acceptance_ledger.dart`,
`proven_elsewhere.dart`, `docs_structure_test.dart`, the three `runLocal.sh`
runners and 30-odd functional test files. The paragraph even carried its own
warning — *"Re-run the check below rather than extending that reasoning to the
next commit"* — and the reasoning was extended anyway, which is the failure it
was written to prevent. **Nothing fires on push on this branch** (the workflow
is `workflow_dispatch` only), so a dispatch is the only way to move this line.
⚠️ The per-suite counts below are from that 2026-08-22 run and several have
moved since — the functional pack is **186** locally as of 2026-08-23, not the
178 named here. CI's own per-suite counts matched the local ones **at that
commit** —
at_auth 342, at_client 1509, at_onboarding_cli 54, at_client_flutter 37,
functional 178, e2e 37, `end2end_test_14` 37, pqe2e 17 — so the green is not a
skipped suite.

⚠️ **This paragraph read "THE BRANCH IS NOT GREEN" and named run `32482877878`
on `9a7260dc7` as newest.** That run's failure is now diagnosed and was never
this branch's code — [14.50](../implementation-plan.md#1450-the-e2e-teardown-revokes-enrollments-belonging-to-other-runs) has it: a
concurrent run tore down this run's enrollments. **The harness defect it found
is still open**, and both green runs since had no other run in flight, so they
say nothing about whether it recurs. The arithmetic here was also wrong: it
said HEAD was "six commits past" `9a7260dc7`; it is **37**.

⚠️ **This paragraph named the older, successful run `32468769474` on
`2965330f1` and called it "the newest", concluding "success, 11/11 jobs".** It
was already false on the day it was written — the red run was dispatched three
hours later, on the same day. It is recorded here rather than deleted because
of *how* it misled: it opened with a staleness warning, hedged, and supplied
the re-derivation command, and all of that reads as diligence, so a reader
trusts the number and skips the command. Run the command.

```bash
gh workflow run at_client_sdk.yaml --ref gkc-pq-d1-spike
gh run list --branch gkc-pq-d1-spike --workflow at_client_sdk.yaml --limit 1 \
  --json headSha,conclusion --jq '.[] | [.headSha[0:9], .conclusion] | @tsv'
git log --oneline -1
```

✅ **The five finished `## TODO` rows were demoted on 2026-08-22.** This
paragraph read "Five `## TODO` rows below are finished and still sit in the
owed table" and named 14.41, 14.43, 14.48, 14.45 and most of 14.39. All five
now have `## DONE` rows and their bodies live in
[`detail/implementation-plan.md`](implementation-plan.md); the genuinely
open residue each left behind was split into its own row rather than being
carried inside a closed one.

### 14.34 An unexplained intermittent in `self_enrollment_retrofit_live_test.dart`

⚠️ **Every open question below was answered on 2026-08-25 and the defect is
fixed.** The atServer received the test's ping before it had processed the
retrofitted client's `monitor:`, so nothing was subscribed and the notification
was written to no connection at all. gkc ruled the fix onto the caller and the
test rather than the protocol; `AtRpc.ready()` and a retried ping shipped, and
the pack has run green carrying them. The diagnosis, the margin measurement, the
four candidates and the live proof are under **G3** above. This is the entry as
it stood while it was still open, kept for its method — the instruction to copy
the atServer log out before `runLocal.sh` tears the container down, and the
bisect point.


⛔ **D1 GATE (gkc, 2026-08-23).** D1 ends when every rail is green, and an
unexplained live-pack failure makes "green" a rate rather than a state.

`tests/at_functional_test/test/self_enrollment_retrofit_live_test.dart` times
out after 40 s at `await firstNotification` (the `.timeout(const
Duration(seconds: 40))` at line 261, awaited at line 290) during a full
functional pack run, and passes when the file runs alone. Seen **1 of 5** pack
runs on 2026-08-17 and **1 of 2** on 2026-08-19 at `327cf4fa2`; the retrofit
sequencing landed between those trees, so the two rates must not be pooled. It
is not a flake and not fixed — record any further occurrence with its
numerator, denominator and tree rather than re-classifying it.

**What the 2026-08-19 occurrence established: the notification WAS
delivered.** The client log carries exactly one `Received
@alice🛠:rf2cmon-57335863.buzz@alice🛠`, on a monitor whose PKAM went out as
`signingAlgo:rsa2048`. Two clients had monitors listening — the legacy owner
and the retrofitted ML-DSA one — and the test awaits the latter. So the open
question is **which monitor the atServer considered a subscriber**, a fact
with no near-side representation at all.

**Already ruled out** (see `decisions.md`): posture and signing algorithm are
not the variable, and the failure is reachable without a retrofit.

⚠️ **`runLocal.sh` ends with `docker compose down`, so a run chasing this must
copy the atServer log out first**: `docker cp test-virtualenv-1:/apps/logs
<dir>`.

**If it recurs,** the bisect point is `0668cf91d` — code there is the
local-key fix without the `_apsk` write serialisation, so green at that commit
pins it on the serialisation.

**A lead from G0, NOT a diagnosis.** G0's mechanism is an atServer sharing one
outbound connection between unrelated relays, because `AtCacheManager` hands
`OutboundClientPool.get` a `DummyInboundConnection` and
`DummyInboundConnection.equals` answers true for any other one. The
**notification** path has the same shape in its own pool:
`NotifyConnectionPool.getOutboundClient` builds a fresh
`DummyInboundConnection()` per call and matches it the same way, so every
notification to a given destination atSign shares one `OutboundClient` too
(at_server `a0deee69`,
`packages/at_secondary_server/lib/src/notification/notify_connection_pool.dart`).

That is a shared mechanism, not a shared cause: this row's open question is
which *inbound* monitor the atServer treated as the subscriber, and nothing
shown so far reaches that from the outbound pool. ⚠️ **This said the two
rates "matching at 1 in 5", and they do not match**: the PQ harness measures
13-22 wrong of 50 — 26% to 44% — against this row's 1 of 5 pack runs and then
1 of 2. They were never the same figure, and a coincidence would not have been
evidence in any case. ⛔ **The G0 lead is DEAD, settled 2026-08-25.** This paragraph proposed
running the pack against a G0-fixed atServer as "the cheap check". It was run —
20 iterations against `at_virtual_env:g0fixed`, which carries the G0 fix — and
the timeout still occurs. The cause is unrelated to outbound pooling: the
atServer receives the ping before it has processed the receiving client's
`monitor:`, so nothing is subscribed and the notification reaches no connection.
The evidence, the margin measurement and the four candidate fixes are in **G3**
in [`## THE NEXT MOVE`](#15-the-lettered-d1-gates-g0g8-as-they-were-discharged); this paragraph is a pointer.

⚠️ **Probably the same phenomenon as
[14.43](implementation-plan.md#1443-the-functional-suites-convergence-race)**
— both are functional-pack convergence waits, both pass when the file runs
alone — but nobody has shown one cause covers both. If 14.43 is worked, work
this row with it.

⚠️ **Also owed, and nearly lost in the 2026-08-23 cut:** The triage owes one
sentence ("diagnose the intermittent") and calls ~28 of 70 lines archaeology,
but two of those lines are the METHOD for the owed diagnosis, not a record of
it. (a) The instruction to copy the atServer log out before `runLocal.sh`
tears the container down — the section says outright that the one occurrence
with evidence had its far-side log destroyed, and the whole investigation now
turns on a fact that exists only in that log. (b) The bisect point and why it
discriminates. Neither is in any commit; both are reasoning about what to do
next.

⚠️ **Also owed, and nearly lost in the 2026-08-23 cut:** The instruction
attached to the owed diagnosis — that this is very probably 14.43's phenomenon
and should be worked with it, and is explicitly not asserted as identical. It
matters more than it reads, because 14.43 has since been FIXED and
re-measured, which 14.34 does not say: whoever picks up this owed D1 gate
should re-measure the rate before diagnosing anything. If the owed rewrite
becomes "diagnose the 40 s timeout", that pointer goes and the work restarts
from the 2026-08-17 framing.



### The `enrollment_submitter` review, and why the recommended fix is wrong

✅ **BOTH FIXED 2026-08-25, on both branches** — see `git log` for `fix(at_auth): a builder failure no longer degrades a first enrollment`. ⚠️ This row read "neither fixed". It is kept because the two corrections below are what stop the review being re-applied as written, and because the at_client half of (b) is NOT on the at_auth carve branch: at_client's PQ secret sharing is not there at all. From srieteja's review of [PR #2179](https://github.com/atsign-foundation/at_client_sdk/pull/2179), 2026-08-25. The other four items in that review are fixed and on both branches.

**(a) A PQ first enrollment can activate with no encapsulation key.** `_buildMetadata` writes the keys into a fresh `InMemoryAtKeysIo`, then wraps only the `builder(keysIo)` call in try/catch — it logs `severe` and returns null. `_handleFirstEnrollmentRequest` submits anyway, with no equivalent of the `isPq`/`keyPackage` guard the OTP path has. ⚠️ **The review calls this permanent capability loss and it is not**: that rested on a doc line saying `metadata.keyPackage` is written only by the request that creates the record, which the code itself retracted on 2026-08-19 — `KeyPackageMinting` rewrites it whole by the enrollment's own `enroll:update`. So it is degraded and recoverable. ⚠️ **The recommended fix cannot be written as stated**: `FirstEnrollmentRequest` has no `keyExchangeMode`, so there is no `isPq` on that path — the only signal is `metadataBuilder != null`.

**(b) `_handleAtEnrollmentRequest` never adopts what the builder filed.** `metadataBuilder` runs before the request so it can advertise a key package, so everything it files lands in the atSign-scope container; after `enrollmentIdFromServer` arrives only the flat APKAM keypair is re-filed under it. `_handleSelfEnrollmentRequest` and `onboard()` both call `adoptMaterials` and this path does not, so `keysForEnrollment(id)` never returns the key package's private half and it is left behind when the enrollment is retired.

⛔ **DO NOT apply the one-liner the review recommends.** Adding `adoptMaterials` at the `enrollmentIdFromServer` assignment breaks the PQ OTP flow: `enrollmentApkamSymmetricKeyResolver` → `keyPackageMaterial(keys)` is called with **no** enrollment id, so re-homing the material under one puts it where that resolver cannot see it. It looks obviously right, which is why it is written down here

### The `## TODO` table as it stood on 2026-08-26, before the collapse to one list

36 rows, several of them ✅ rows kept only to record what had been done, which
is what the live plan no longer holds. Reproduced verbatim so no residual is lost
in the condensation — where a row's residue is still owed, it is a priority row in
the live plan.

| Item                            | What is owed                                                        | Blocked on                                                                       |
|---------------------------------|---------------------------------------------------------------------|----------------------------------------------------------------------------------|
| **at_chops 3.6.1 — [PR #2181](https://github.com/atsign-foundation/at_client_sdk/pull/2181)** | ⛔ **MERGED 2026-08-24, and NOT yet published — pub.dev tops out at at_chops `3.6.0`, so what is owed here is the publish, not the review.** ⚠️ This row read "Carved and OPEN" until 2026-08-24. It is NOT in the train's ordering above** — it was cut on 2026-08-24 from trunk, not from the spike, because at_chops 3.6.0 is already published and had no in-progress CHANGELOG heading to fold into. Message-only change: `PkamMlDsa65SigningAlgo.sign` reported a bare `ML-DSA-65 secret key must be 4032 bytes: N`, which names neither the credential nor the likeliest cause. A PKAM key of ~1.2 kB is an RSA-2048 private key, which a caller holds by naming one enrollment's algorithm while carrying another's credentials. Owed: merge, then gkc publishes 3.6.1. ⚠️ **Nothing depends on it** — no floor in this tree requires 3.6.1, so it can land whenever; but it is a second at_chops publish the train's ordering does not mention | Nothing. It is independent of at_auth and of the spike |
| `acceptance-report.json` is ignored only on this branch | ⚠️ **Deferred by gkc 2026-08-25 — recorded so the deferral is not silent.** `.gitignore` here carries `acceptance-report.json`, `citations.jsonl` and `acceptance-ledger.md`; **trunk carries none of them** — ⚠️ this also named `gkc-pq-d1-at-auth`, which was deleted on 2026-08-25 once #2179 merged. A per-run report is sitting in `packages/at_auth/` at 220 KB, and on the carve branch a `git add <directory>` wants to track it — the commit hook refused exactly that on 2026-08-25.<br><br>⚠️ **gkc's reason was that [PR #2179](https://github.com/atsign-foundation/at_client_sdk/pull/2179) merges to trunk shortly, and that does not by itself fix it**: #2179's head is `gkc-pq-d1-at-auth`, which is the branch LACKING the ignore. Trunk gets it when this branch merges, not when #2179 does | Nothing. It resolves itself when this branch lands; until then, name files rather than directories when staging on the carve |
| **the rollout posture is inert, and the default must move to `pqReady` in this RC** | ✅ **RULED BY gkc 2026-08-25 in a grilling session, and ALL FOUR STEPS LANDED 2026-08-26** — see the cell to the right, which carries what each step cost. ⚠️ This headline read `the work is NOT started` for a day after the work finished, while its own cell recorded steps (1) to (4) done: a header contradicting its own body, found by a cold read rather than by the session that caused it. ⚠️ Several of these findings contradict things this doc and the code say, so read the whole row before acting on any part.<br><br>**What `PqPosture.legacy` MEANS** (gkc, verbatim): *"do nothing more than you would have done if built with at_client 3.13.0. It's really attempting to ensure we can make a program pretend to be legacy even though it has been built using latest packages. In particular — no retrofitting, no minting, no interest in secret sharing notifications, none of that."* It exists **for compatibility testing**. A second requirement rides with it: an approver must be able to approve enrollment requests from ACTUAL legacy clients as well as PQ-aware ones, because old clients still enrol during the transition.<br><br>**Measured: the posture is largely inert.** `PqPosture.keyExchangeMode` is declared, compared, and documented as part of "the whole of what a posture can change" — and **nothing in any package's `lib/` routes it into an enrollment request**. That is by design as far as at_client goes (`pq_posture.dart`: *"at_client submits no app enrollment, so they take effect when the app builds its `AtEnrollmentRequest` from the posture"*), but **both real callers ignore it, in opposite directions**: `at_onboarding_cli` builds the unnamed `AtEnrollmentRequest(...)`, which hard-sets `legacy`, so `enroll --posture pqActive` gets no key package; the functional harness always built pq, so a `PqPosture.legacy` cell got a key package and joined the substrate. The CLI half is the one that ships and is unfixed.<br><br>⛔ **Two things that sound true and are NOT.** (1) *"Abstention falls out for free from `keyExchangeMode`"* — no: a legacy-mode enrollment still registers a key package at runtime, because `conveyed_key_collection.dart` calls `register()` unconditionally at every client start. Measured: a legacy-mode cell enrolled without a key package and prepared one anyway. (2) *"The harness should derive the mode from `preference.posture`, as app authors are told to"* — tried and reverted: `AtClientPreference` defaults `posture = PqPosture.legacy`, so every caller naming no posture silently switched to legacy-mode enrollment. Measured: **seven substrate tests went red at once**. The harness takes an explicit `keyExchangeMode` defaulting to pq instead.<br><br>⚠️ **The grid's legacy cell was never a legacy client, so arm 2 has been proving less than it claims.** And the property `pq_posture_grid_test.dart` asserts — *"one that does not seed never acquires it"* — is **not implemented**: `filePending` files every `__nskey.` secret in the store unconditionally at every client start, and the non-seeding cell files the namespace private in every run. What actually protects that assertion is a **167–210 ms margin** across five runs between the readback and the acquisition. The faithful un-upgraded peer already exists and is a different *binary*: `tests/pq_matrix/published` on at_client **3.14.0**, spawned by `pq_released_peer_test.dart`.<br><br>**THE RULING, and the order is safety-critical.** The default posture moves to **`pqReady` in this release candidate** (`pqActive` at 4.0.0), and **every test states its own posture** — classified by what it exercises: substrate → `pqReady`, PQ-by-default writes → `pqActive`, posture-agnostic or compat → `legacy`. **51 `getPreference` sites across 29 files, 8 already explicit, so ~43 to decide.** ⛔ **The e2e pins land BEFORE the default moves.** `tests/at_end2end_test`'s atSigns `@ce2e1..@ce2e4` are long-lived and never recycled; that pack's `dart_test.yaml` already refuses PQ test *files* by allowlist, but an allowlist cannot see a posture — flip the default first and the allowlisted tests write signing keys, `_apsk` and namespace keys to those atSigns through the front door, permanently, with nothing going red. Enforcement gkc chose: **the e2e pack's preference helper takes `posture` as a REQUIRED parameter**, so the compiler names every site and a new test cannot be written without choosing. ⚠️ **The classification's sharpest finding, and it would cause SILENT damage: approver and fixture clients must be `legacy`.** Seeding is the only posture-gated step in the whole PQ bootstrap (`pq_client_bootstrap.dart`, `if (getPreferences()?.seedNamespaceKeys != true) return;`) — every other step, key-package reconcile included, runs under `PqStartupGates` defaults no posture touches. ⚠️ **That sentence is true under its qualifier and misleading without it, measured 2026-08-26: the posture gates the RETROFIT as well, and the retrofit is not a bootstrap step.** `AtClientImpl._init` calls `_settleEnrollmentIdentity()` (`at_client_impl.dart:663`), which compares `preference.authenticationKeyAlgorithm` against the algorithm the enrollment holds and retrofits when the posture asks for a stronger one — `retrofitIsDue` is `held != wanted && strongestOf({wanted, held}) == wanted`, and its dartdoc says outright **"There is no preference opt-out."** So legacy→pqReady moves four axes, not one: `rsa2048` → `mldsa65` authentication, `{}` → `{rsa2048}` data signing, `seedNamespaceKeys` false → true, and `keyExchangeMode` legacy → pq. A client holding **no** enrollment id is untouched by the first of those (`_settleEnrollmentIdentity` returns immediately), which is why the demo-atSign clients keep authenticating with their RSA PKAM keys — but every client that holds an enrollment id AND an `AtKeysIo` retrofits. In this pack that is 15 files using `enrolAndAuthenticate` and 28 naming an `atKeysIo`. So an approver at `pqReady`/`pqActive` publishes `public:__nskey.<ns>@<atSign>`, because `NskeySeeding.authorisedNamespaces()` returns `{preference.namespace}` for a legacy-PKAM client with no enrollment id — which is what an approver is. That destroys the grid's readiness axis and mints the namespace key before any cell does, moving the private into the approver's keyfile. **It stays green while doing it.** A naive reading of "classify by what the test exercises" invites exactly this, since an approver does drive key packages and conveyance.| Nobody yet. **Ordered:** ✅ **(1) DONE 2026-08-26** — `posture` is a required parameter on `TestPreferences.getPreference`, on `TestSuiteInitializer.testInitializer` and on `ConcurrentClients.open`, and all **83** sites the compiler named across 18 files are pinned to `PqPosture.legacy`. ⚠️ **Three findings that shaped it.** The helper memoises per atSign, so a second ask naming a different posture is refused — without that the parameter would be decorative for every atSign used twice. `testInitializer` applied the helper as an internal default (`atClientPreference ??=`), so requiring it on the helper alone would have left every caller there naming nothing; that is where most of the sites are. And `notify_with_isolate_test.dart` builds an `AtClientPreference` directly inside a spawned isolate, which no compiler names — pinned by hand. ⚠️ **Every e2e site went to `legacy` deliberately, including the 29 under `test/pq/`**: nothing in that pack named a posture before, so legacy IS its current behaviour, and step 1 changes none of it. **Owed, and not decided:** classify the six `test/pq/` files by what each exercises, with a pq e2e run behind the choice. They run against a throwaway virtualenv, so there is no safety reason to leave them there — only the absence of evidence. ✅ **(2) DONE 2026-08-26** — `posture` is required on `TestUtils.getPreference` and on `TestUtils.initAtClient`, and the compiler named **103 sites across 55 files**. ⚠️ **The "~43 sites" figure was an undercount and so was "51 across 29 files"**: both counted `getPreference(` alone and missed every `initAtClient` caller taking the internal `preference ??=` default, which is where most of them are. All pinned to `PqPosture.legacy`, the default they already ran at, then classified. ⛔ **The classification moved NOTHING, and that is the finding.** Every PQ-tagged test drives its subject through the API — `NskeySeeding(...).seed()`, `ring.mintAndPublish(...)` — or varies one axis directly (`apsk_server_side_test` passes `dataSigningKeyAlgorithms` while the posture stays legacy). **No functional test sets `seedNamespaceKeys` or `writesPqByDefault` by hand** — searched with a proven control, the only hit is a `reason:` string. That is why they are all green at legacy: none of them relies on the posture to switch its subject on. **One change, in the opposite direction:** `crypto_era_default_test` reads the new `TestUtils.sdkDefaultPosture` rather than naming a constant, because its subject IS the default — pinned to `legacy` it would go on passing after step 3 while measuring a posture the SDK had left, since `pqReady` also carries `writesPqByDefault: false`. ⚠️ **What proves the flip in step 3, then:** the grid's own `pqReady` and `pqActive` cells, which are explicit and unaffected by the default, plus that one default-following test. Nothing else in the pack exercises the default, by design — a test that named nothing would change meaning under every release that moved it. Also landed here: `pq_tag_test`'s matcher listed a bare `PqPosture`, which after the pin flagged all 55 files including its own negative control; narrowed to a non-legacy posture, measured at 34 flagged against 34 tagged with none lost, both directions re-proven by mutation; ✅ **(3) DONE 2026-08-26** — `AtClientPreference.posture` defaults to `pqReady`. **Eight unit tests went red and only two were the flip's own business.** ① A client with **no `AtKeysIo` was publishing a namespace key it could not keep**: `_seedNamespaceKeys` gated only on `seedNamespaceKeys != true` while its sibling steps already checked for a key source, so `filing` was null and `_mint` took its `severe` branch — peers sealing to a key that dies with the process. Gated, and that restores what `no_atkeysio_inertness_test` pins. ② `startup_call_order_test` looked like an ordering inversion and was **not**: `firstIndex('cmd:enroll:list')` is a PREFIX match and seeding emits `cmd:enroll:listns:<ns>` four events earlier, so under a non-seeding posture the loose prefix found the sweep by luck. Tightened to `cmd:enroll:list:`. Four more were pins that DEFINED the old default and their edits are the review (`pq_posture_test` ×2, `signing_key_minting_test`, `nskey_seeding_test`); one was `signing_algo_resolution_test`, whose legacy enrollment no longer falls back but **retrofits**, reaching a call its `MockRemoteSecondary` never modelled; and one was the acceptance suite's `provenIn` citation rail catching a test rename. ⚠️ **A gap in step 2 that only the live pack found:** four **direct** `AtClientPreference()` constructions in `enrollment_test.dart` and `sync_multiple_client_test.dart` bypass `TestUtils` entirely, so no compiler named them and the pin missed them. Step 2's own refusal caught it — but **inside a spawned isolate, where it presents as a 30-second timeout, not an error**. All four pinned. ⚠️ **`_apsk` publication is NOT posture-gated and never was** — `pq_client_bootstrap.dart:41`: `KeyPackageRegistration.register()`'s `publishPublicSigningKey` "lives outside the startup and is not gated by this object". So the e2e clients, which all hold a `FileAtKeysIo` from `_nskeyKeyfileFor`, publish `_apsk` on `@ce2e1..@ce2e4` today and did before this work; the pins stop seeding and retrofit, not that. Measured: the full e2e run is **identical either side of the flip** — `publishPublicSigningKey` 93, `PublishedNskeyKeyRing` 26, `NskeySeeding` 2, `__nskey` 30, `_apsk` 53 — and the non-PQ set alone shows `__nskey` 0, `NskeySeeding` 0, `PublishedNskeyKeyRing` 0, retrofit 0, with the full run as the positive control. ✅ **(4) DONE** — functional 183/183, e2e 62/62, non-PQ e2e 37/37, at_client unit 1571/1571. ⛔ **AND THE PIN IS NOW A MECHANISM, not a convention** (gkc asked for an absolute guarantee that nothing drives a retrofit on `@ce2e1..@ce2e4`, 2026-08-26). `TestPreferences.refuseDurableWritesToLongLivedAtSigns` throws for those four atSigns when a preference would write state that outlives the run. ⚠️ **It checks the AXES, never the posture's identity, and that is the whole design.** `authenticationKeyAlgorithm`, `dataSigningKeyAlgorithms` and `seedNamespaceKeys` are each settable BESIDE a posture — and `retrofitIsDue` reads the algorithm, not the posture — so `posture == PqPosture.legacy` would wave through a preference that retrofits. Called from all three routes this pack has to a live client: `getPreference`, `testInitializer` (which also catches a preference a test built by hand and passed in) and `notify_with_isolate_test`'s isolate-local builder, which reaches a client through neither helper. Enumerated, not assumed: every `setCurrentAtSign` in the pack takes its preference from one of those three. `long_lived_atsign_guard_test.dart` holds it — 8 tests, on the allowlist so CI runs it — with negative controls (legacy is allowed there; a throwaway atSign is not restricted) and **four mutations, one red each**: keying the guard on the posture reds only the three axis cases, dropping the call from the helper reds the wiring case, and removing an atSign from the set reds the case that parses `config14.yaml` and `config23.yaml` and asserts the set covers every atSign they name — so adding a fifth atSign to a config goes red rather than silently unguarded. ⚠️ **One hole was left open and then closed the same day:** a guard only refuses what passes through it, and a future test could build its own preference and call `setCurrentAtSign` itself, going round all three doors. None does today — every one of the pack's 45 `setCurrentAtSign` sites was traced to a guarded door — but nothing kept it that way. A ninth test now refuses any file that constructs an `AtClientPreference` without invoking the guard, proven by adding an unguarded construction to `bypasscache_test.dart` and watching it name that file. ⚠️ Do NOT reorder — (3) before (1) is the one-way door. Also owed and separate: route `keyExchangeMode` in `at_onboarding_cli`. ⚠️ **Still owed after 2026-08-26's CLI work, and the gap is now narrower and easier to misread as closed.** That day fixed the *authentication* axis — `enroll` and `sendEnrollRequest` took `signingAlgo` defaulted to a hardcoded `rsa2048` while `authenticate()` stamped the connection from `preference.authenticationKeyAlgorithm`, two defaults for one fact that agreed only until the shipped default moved, at which point at_chops refused an RSA-2048 key carrying an ML-DSA-65 declaration. `signingAlgo` is nullable now and resolves from the preference. **The key-exchange axis did not move**: `sendEnrollRequest` builds the UNNAMED `AtEnrollmentRequest(...)`, whose initialiser hard-sets `keyExchangeMode = EnrollmentKeyExchangeMode.legacy` — only the `.pq` named constructor sets `pq`. So `enroll --posture pqActive` now mints an ML-DSA APKAM key and still enrols in legacy key-exchange mode, advertising no key package. Not broken — the approver's `mintsSymmetricKey` test reads the absent package and takes the RSA path consistently, and both functional legs are green — but it is not what the posture names. **Fixing it means choosing the constructor by the posture's `keyExchangeMode`, not adding another parameter**, which would be a third source for one fact. ⚠️ Two more findings from the same day, both about tests nothing runs: `at_contact` is in `at_libraries.yaml`'s `build` job (pub get + analyze, **no tests**), so its five live group tests had failed since the 2022 package move without ever reddening CI — now skipped, with what they need stated at the skip; and its sibling `at_contact_tests.dart` holds **11 more the runner has never collected**, because the filename does not end in `_test.dart` |
| **a receiver drops a pqActive notification because its own nskey request goes unanswered** | ✅ **FIXED 2026-08-25.** ⚠️ This row read "⛔ **DIAGNOSED** … Nobody yet. **What is owed:** read the nskey conveyance path and settle whether a holder conveys once per requesting enrollment or broadcasts once for the atSign". That question is answered and the fix is in: addressing was never the problem — every hop is already sealed to the requester's key-package id.<br><br>**The cause.** A holder decided "another holder already answered this requester" by scanning for **any** envelope addressed to that requester's kpid in the namespace. Every envelope — request, answer and unsolicited push — carries the same address shape, and a request fans out **one record per other roster member**, so a third enrollment's own broadcast put a record at the requester's address that read as an answer. Holders that could serve the request stood down; the requester waited out its window and its parked notification was dropped. The rate cap immediately below that gate was already keyed correctly on (requester, secret name) — the coarser gate short-circuited it.<br><br>**The fix, six changes.** (1) The stand-down is `warning` and names the envelopes it matched. (2) `NskeySeeding._convey` writes the minted private into the secret store, so the minter can answer a pull for what it just minted — the answering path reads that store and `hydrateStoreFromFiling` runs before the mint. (3) One named `NskeyPrivateFiling.conveyanceWait`, with `NotificationServiceImpl.parkTtl` derived to sit **above** it: the park was 2 minutes against a 5-minute pull, so a conveyance that merely succeeded slowly still lost the notification. (4) The envelope address gains a correlation segment — `<msgId>.<inReplyTo>.<kpid>.__ssenv.<ns>@<atSign>` — with the id travelling in the **sealed** payload and the copy in the key name a routing hint only. (5) The suppression scan narrows to answers to *that* request. (6) `_askedConveyance` becomes a 5s cooldown rather than never expiring, so a client whose one broadcast reached only holders that could not serve it asks again.<br><br>**Measured, same image (`at_virtual_env:g0fixed`), same rig, same machine: 0 red of 5, against 3 red of 5 before.** Durations 308–312s against reds of 459–462s. ⚠️ **That bounds a rate; it does not prove the failure is gone** — the stronger evidence is the mechanism: across all five runs r-pqActive **files** the key (0 of 3 in the reds), and there are **0** notifications parked, **0** dropped and **0** suppressions of its requests. Positive control: the new warning does fire in those same logs for other requests, so those zeros are absences rather than a filtered stream.<br><br>⛔ **A seventh change was built and REVERTED, and the reason matters more than the change.** It filed nskey privates arriving after the start-time drain. It also filed *unsolicited* pushes, so a `seedNamespaceKeys = false` posture began acquiring namespace keys — `pq_posture_grid_test.dart`'s *"the recipient enrollment holding the namespace private reads what was written"* went red **5 of 5**, its `reason:` naming exactly the guarantee: *"One that does not seed never acquires it … it is why a rollout seeds a stage BEFORE it switches writes over."* The mechanism it aimed at is real — an answer that lands after `waitForSecret` gives up is filed by nothing — but closing it must not hand key material to a posture that never asked. | Nobody yet, and only one thing is owed: **file a late-arriving nskey private only for a generation this client actually asked for.** The reverted attempt filed any arrival, which is what breached the seeding guarantee. ✅ **The second mint path is CLOSED 2026-08-25.** ⚠️ This row said `PublishedNskeyKeyRing._mint` "never reaches `_convey`, so a generation minted during rotation still leaves that client's store unprimed". Half right: the rotation path *does* convey — `NskeyRotation.rotateNamespaceKey` pushes the successor to the roster — but it never primed **its own** secret store, so the one enrollment certain to hold the successor was the only one that could not serve a pull for it. It now calls `putIfNewer` before the fan-out, exactly as the mint-time convey does. The two entry points into `_mint` are enumerated and both covered: `mintAndPublish` (reached only from `nskey_seeding.dart`) and `rotate` (only from `nskey_rotation.dart`) — counted two ways, by `git grep --untracked` and by a `find`-driven `grep -l`, agreeing on the same two files. ⚠️ One consequence is now stated in that method's dartdoc and was verified against the answer path before it shipped: `excludeEnrollmentIds` filters the rotation PUSH and not a later PULL, so an excluded enrollment still on the namespace roster can ask for the successor and be answered — rotation-to-exclude is not a revocation on its own. **Re-derive the rate**, never quote it — five runs of `runLocal.sh` with `VIRTUALENV_IMAGE=at_virtual_env:g0fixed`, then per run `grep -c "Dropping parked notification"` and check whether r-pqActive logged `Filed the nskey private`, against the `##GRID## up:` lines that map each cell to its `runningAs` id |
| **the at_client carve has a stack design, and five decisions before it can be cut** | ⚠️ **The design exists but is INVISIBLE to git.** gkc asked on 2026-08-25 for a plan of stacked pull requests for the at_client release candidate — each layer reviewable on its own, each with a description saying why and what rather than how, the tests it adds, and where a reviewer should spend attention. It was built and checked against the real diff, and it lives at **`untracked/at-client-stacked-prs.md`**, which `/untracked/` in `.gitignore` hides — so `git grep` cannot find it, nobody else has it, and a fresh session searching the repo will conclude no such plan exists. **Nine layers**, cut on the line that most of the branch is inert until one late layer switches it on: read 2, 3 and 7 properly, skim the rest.<br><br>**Five decisions it cannot make, and the stack cannot be cut until they are made:** two files are claimed by two layers (`pq_signing_root.dart` and `pq_signing_chain.dart`, in both 4 and 6 — sized into 4, which would make 6 about 2,300 lines smaller than its row says); the unit suite is deliberately red in the middle of the stack because two tests cover code that arrives later, while four layers say to verify with a whole-package run; one new test file appears in two layers and lands in only one; one layer says its wiring "lands elsewhere in the stack" without naming the layer, and is reviewed before that layer exists; and four areas of the diff fell outside every layer — **a file in no layer never lands**.<br><br>⚠️ **One of those four is a trap worth keeping even after the stack is cut.** Two already-published packages look like a formatter run and mostly are — 21 of 22 changed files in one and 7 of 8 in the other are byte-identical once all whitespace is removed. But two are not, and one of them is a hand-written format pin, which is the single kind of file that must never be skipped on the strength of its neighbours. Test it by comparing each file with whitespace stripped, never by reading line counts | Whoever cuts the stack. Not a D1 gate |
| **at_client cannot ask for a write that skips the commit log** | ✅ **BUILT 2026-08-25.** ⚠️ This row read "⛔ **ASKED FOR BY gkc, as the next piece of client work**" and described it as owed. Kept for the two traps and the compatibility finding, which apply to any later caller reaching for the same flag; **G8** in [`## THE NEXT MOVE`](#15-the-lettered-d1-gates-g0g8-as-they-were-discharged) carries what landed and what was measured. The original follows. at_client writes records to the remote atServer that should drive no commit-log entry — the immutable lock records, each carrying a small time-to-live so it expires quickly, and each still costing a permanent commit-log entry that every other client of that atSign syncs. **The design, the verified premises and the two traps are in G8 in** [`## THE NEXT MOVE`](#15-the-lettered-d1-gates-g0g8-as-they-were-discharged); this row is a pointer.<br><br>**The three premises, all checked in source 2026-08-25 rather than taken on trust:** the atServer implements it on its trunk (`update_verb_handler.dart`, `update_meta_verb_handler.dart` and `delete_verb_handler.dart` each pass `skipCommit: verbParams[WireParams.noCommit] != null`, so it is in the canary and therefore in `dev_env` and the local virtualenv); at_commons carries `noCommit` on both verb builders, emitting `:nc`, with the syntax parsing it at three sites — and ✅ **it is in the published at_commons 5.16.0**, which at_client already floors at, so no version change and no publish are needed; and at_client has **zero** occurrences of it.<br><br>⚠️ **The obvious shape of the fix misses the records that motivated it.** Adding the flag to `PutRequestOptions` and `DeleteRequestOptions` does not reach the lock writers, because they do not call `put()` — `crypto/nskey/mint_lock.dart:139` goes straight to `getRemoteSecondary()!.executeVerb(UpdateVerbBuilder() …)`. Grep the builders, not the options classes.<br><br>⛔ **And three hand-built command strings must NOT get it**: `sync_service_impl.dart` builds `'delete:$atKey'`, `'update:$atKey …'` and `'update:meta:$keyWithMeta'` as strings, and that is sync replaying local changes onto the remote. Suppressing the commit entry there is how another client stops seeing the change | Nothing. ⚠️ One correction worth carrying: this row said an older atServer would refuse the command as invalid syntax. It does not — it parses the flag, ignores it, and records the commit anyway, silently |
| **dependency floors below what the code needs** | ✅ **SWEPT AND FIXED 2026-08-25.** ⚠️ This row read "⛔ **CARVE-TIME BLOCKER for at_client_flutter and at_onboarding_cli**" and listed the two as owed; both were raised to `^3.15.0-rc1` the same day and both packages analyze clean (at_onboarding_cli's unit suite 54, exit 0). The row is kept for the METHOD and the two traps in it, which apply to every later carve. Measured 2026-08-25. The at_commons floor fixed the same day was one instance of a class, and this is the sweep the train row asked for.<br><br>**Method, and it is cheap enough to repeat**: a floor below the version the workspace actually resolves is a version this tree has never compiled against. Compare each declared floor against `pubspec.lock` (and, for a path-resolved sibling, against that sibling's own `version:`). ⚠️ **That over-reports**, because a low floor is harmless when another dependency's constraint dominates the intersection — at_client_flutter's `at_commons: ^5.8.0` is masked by its at_client dependency, which requires `^5.16.0`. Only an **unmasked** gap is a defect, so check what else constrains the same package before acting on a row.<br><br>**at_client itself is clean** once at_commons was fixed. Its two remaining sibling gaps were checked and are genuinely fine: `at_utils ^3.2.0` against a resolved 3.4.0 — at_client uses neither `CLILoggingHandler` (new in 3.4.0) nor a mixed-case logger level, and 3.3.0 was dependency bumps only; and `at_chops ^3.6.0` against 3.6.1, which is a diagnostic message and no new API.<br><br>**The two real ones, both unmasked and both proven by symbol against the published package:**<br>• **at_onboarding_cli declares `at_client: ^3.10.0`** and names `PqPosture` **12 times** in its `lib/`. `PqPosture` is in no published at_client — 0 hits in 3.14.0, the newest on pub.dev. A consumer resolving at that floor gets a package that does not compile.<br>• **at_client_flutter declares `at_client: ^3.14.1`** and names `PqPosture` and `EnrollmentConveyanceException`, both absent from at_client 3.14.0. (Positive control for that search: `AtClient` is found in 11 files of the same package, so the zeros are real.)<br><br>⚠️ **And a second fault in the same two lines, which raising the number alone does not fix**: a caret constraint whose lower bound is a STABLE version does not accept a prerelease, so `^3.14.1` will not resolve at_client `3.15.0-rc1` however published it is. Both must be written as `^3.15.0-rc1`. That is [14.49.2](implementation-plan.md#14492-every-remaining-package-publishes-as-a-release-candidate)'s rule arriving as a compile error rather than as a policy, and raising the number alone would have left it in place | Nothing on these two. ⚠️ **The third-party floors were NOT swept** — at_client alone declares seven of them below what it resolves (`path`, `crypto`, `uuid`, `archive`, `http`, `async`, `meta`), all minor or patch gaps and none checked against first use. Lower risk, and still unmeasured |
| **the `monitor:` verb has no acknowledgement** | ⚠️ **NOT D1, and it is a protocol seam across three repositories.** A client writes `monitor:` and there is nothing to read back — at_server's `MonitorResponseHandler` returns the empty string on success — so it cannot tell acceptance from refusal, and reports a connection as up the moment the command is *written*. Specified upstream as [at_protocol#367](https://github.com/atsign-foundation/at_protocol/issues/367) with three open sub-issues: at_commons [#2175](https://github.com/atsign-foundation/at_client_sdk/issues/2175) (a `prompts` parameter on the verb, opt-in and additive, and it ships first), at_server [#2764](https://github.com/atsign-foundation/at_server/issues/2764) (answer the command, and terminate every notification with a prompt), at_lookup [#2176](https://github.com/atsign-foundation/at_client_sdk/issues/2176) (send it, wait for the answer, frame on the prompt).<br><br>⛔ **A correction to that specification, to settle BEFORE anyone builds it.** #367 says the acknowledgement lets "a refused `monitor:` be reported as a failure". Today `monitor:` is **not** refused: `MonitorVerbHandler.processVerb` checks only that the connection is authenticated, subscribes it, and the refusal then happens per notification inside `_sendNotification` via `isAuthorized`, dropping each one with a server-side warning the app never sees. A replay does not rescue it either — replayed notifications go through the same check. So the acknowledgement ALONE does not fix the case #367 leads with; at_server must also decide the refusal **at `monitor:` time**. #2764 gestures at this ("A refusal must be answerable too") as an aside rather than as the work. ✅ **Verified independently against at_server by the session working there, 2026-08-25**: `processVerb`'s only gate is the authentication check, everything after it is regex parsing and subscribing, and the per-notification refusal logs a server-side warning naming the notification and the enrollment. That warning is the **only** record a dropped notification leaves — so from the app's side a refusal and a sender that never sent are identical, which is the same attribution problem the ordering defect in **G3** had.<br><br>⚠️ **Cost, so the deferral is a decision rather than a drift**: at_server is a separate repository and needs the at_commons carrying the parameter *published* before it can be written against it, and at_lookup's half re-does a release-train position that has already shipped (3.7.0-rc1). ⚠️ **This also said the parameter "needs a version gkc chooses" because at_commons is published at 5.16.0 with no in-progress heading. That is wrong**: trunk and this branch are both at 5.16.0, but [PR #2182](https://github.com/atsign-foundation/at_client_sdk/pull/2182) is open and already bumps at_commons to **5.17.0**, so the parameter folds into an in-progress heading that exists — on another branch, which is why a check scoped to this one missed it. Re-derive with `gh pr list --repo atsign-foundation/at_client_sdk --state open` rather than reading a version out of the working tree. The window it closes is measured in **G3** | gkc scheduling it, after the release train. The caller-side mitigation is already built — see G3 |
| **atServer outbound connection pooling and concurrency** | ⚠️ **IN ANOTHER REPO (`at_server`), and gkc asked for it as a discussion rather than a change** — 2026-08-24, when he took pool keying out of the G0 fix: *"I'd rather serialize on a single connection for now, and have a longer discussion on how to handle outbound connection pooling and concurrency at a later date"*. Recorded so the deferral does not read as a decision.<br><br>**What that discussion has to weigh**, all established while diagnosing G0: every relayed lookup to a remote atSign now serialises behind every other one, and a request queued on the mutex is waiting before its 5 s read budget even starts; `InboundConnectionImpl.equals` matches on remote address and port rather than object identity, so keying on "the real inbound connection" is not the identity keying it sounds like; `NotifyConnectionsPool.getOutboundClient` has the same non-atomic get/connect/add shape that G0 fixes in `getClient`; and `PolVerbHandler` holds a third `DummyInboundConnection`, so pol's `lookUp`/`plookUp` share a pooled client with relayed lookups at `handshakeRequired: false` <br><br>**Four residual findings belong to this discussion**, all pre-existing and none claimed by the G0 fix: `poolSize` is not enforced across different pool keys, so concurrent misses for different atSigns can take the pool past its declared maximum; an evicted client is dropped without `close()`, leaking its socket; `OutboundMessageListener` can queue a bare `@atSign@` prompt as its own entry when the response and the prompt arrive in separate socket reads, and `read()` accepts a bare prompt as valid — a mis-pairing channel a mutex does not touch, since making an exchange's two steps adjacent never validates or drains the queue; and there is no bound on a slow-but-alive peer. The bare-prompt path has exactly **one** sighting in the wild — a single `FormatException` in the g0base arm — which is a sighting and not a rate | gkc scheduling it. Not a D1 gate |
| **at_auth `enrollment_submitter`: two defects from the #2179 review** | ✅ **BOTH FIXED 2026-08-25, on both branches** — see `git log` for `fix(at_auth): a builder failure no longer degrades a first enrollment`. ⚠️ This row read "neither fixed". It is kept because the two corrections below are what stop the review being re-applied as written, and because the at_client half of (b) is NOT on the at_auth carve branch: at_client's PQ secret sharing is not there at all. From srieteja's review of [PR #2179](https://github.com/atsign-foundation/at_client_sdk/pull/2179), 2026-08-25. The other four items in that review are fixed and on both branches.<br><br>**(a) A PQ first enrollment can activate with no encapsulation key.** `_buildMetadata` writes the keys into a fresh `InMemoryAtKeysIo`, then wraps only the `builder(keysIo)` call in try/catch — it logs `severe` and returns null. `_handleFirstEnrollmentRequest` submits anyway, with no equivalent of the `isPq`/`keyPackage` guard the OTP path has. ⚠️ **The review calls this permanent capability loss and it is not**: that rested on a doc line saying `metadata.keyPackage` is written only by the request that creates the record, which the code itself retracted on 2026-08-19 — `KeyPackageMinting` rewrites it whole by the enrollment's own `enroll:update`. So it is degraded and recoverable. ⚠️ **The recommended fix cannot be written as stated**: `FirstEnrollmentRequest` has no `keyExchangeMode`, so there is no `isPq` on that path — the only signal is `metadataBuilder != null`.<br><br>**(b) `_handleAtEnrollmentRequest` never adopts what the builder filed.** `metadataBuilder` runs before the request so it can advertise a key package, so everything it files lands in the atSign-scope container; after `enrollmentIdFromServer` arrives only the flat APKAM keypair is re-filed under it. `_handleSelfEnrollmentRequest` and `onboard()` both call `adoptMaterials` and this path does not, so `keysForEnrollment(id)` never returns the key package's private half and it is left behind when the enrollment is retired.<br><br>⛔ **DO NOT apply the one-liner the review recommends.** Adding `adoptMaterials` at the `enrollmentIdFromServer` assignment breaks the PQ OTP flow: `enrollmentApkamSymmetricKeyResolver` → `keyPackageMaterial(keys)` is called with **no** enrollment id, so re-homing the material under one puts it where that resolver cannot see it. It looks obviously right, which is why it is written down here | gkc scheduling them. Neither blocks the 4.0.0-rc1 publish |
| **atServer: concurrent cross-atSign lookups are answered pairwise** | ✅ **DONE — diagnosed, fixed, verified on the real wire, and [at_server PR #2771](https://github.com/atsign-foundation/at_server/pull/2771) merged to at_server trunk on 2026-08-25** as merge commit `8f4a985a`. ⚠️ This cell read "what is owed is the MERGE … which is open", and before that carried its own copy of the measurements, saying "the branch is unpushed" while G0 said it was pushed. The table of measurements, the mechanism and the controls are in **G0** in [`## THE NEXT MOVE`](#15-the-lettered-d1-gates-g0g8-as-they-were-discharged); this row is a pointer. ⚠️ **The merge does not rebuild `at_virtual_env:local`** — that tag is still whatever tree last built it | One rig action: rebuild the local virtualenv image from at_server trunk before the next live run that needs a fixed atServer |
| **several content keys alive for one `(nskeyOwner, namespace)` scope** | ⚠️ **A second defect, found while diagnosing G0 and separate from it.** One CK per writing enrollment per scope, cut at that enrollment's first write, no re-minting — three sender enrollments produced three CKs under `(bob, ns)` and three under `(alice, ns)`. `CurrentCkPointer` is the only thing meant to converge them and cannot as written: it is put **`localOnly`** into each enrollment's own store and reaches siblings only by sync, so cold enrollments writing together each read no pointer and each mint. `CkManager._resumeCurrent`'s "cutting a fresh one" fired **zero** times across the run. Sync dropped four of those pointer writes, logging `sync queue race: __ckcur.… missing persisted record; removing`.<br><br>**Why it matters beyond waste**: `rotateContentKey` supersedes only the CK in hand, so a rotation asking for forward secrecy leaves the other enrollments' keys live and their data readable — read from the source, **not run**. The measurements are in **G0** in [`## THE NEXT MOVE`](#15-the-lettered-d1-gates-g0g8-as-they-were-discharged) | gkc ruling on whether one CK per enrollment per scope is the intent. If not: the pointer needs a remote-first write taken with an atomic verb or an interlock, and rotation needs to supersede every CK in scope |
| arm 2's UC-G1.15 read returns a content key | ⛔ **DIAGNOSED, FIXED and VERIFIED — it is an atServer defect with nothing PQ about it.** The substance, the measurements and the ruled-out list all live in **G0** in [`## THE NEXT MOVE`](#15-the-lettered-d1-gates-g0g8-as-they-were-discharged); this row is a pointer and must not grow a second copy. ⚠️ It carried its own copy until 2026-08-25, and the two had already begun to disagree | Nothing here — G0 names what is owed |
| spike CI result read, and 12 commits behind | ✅ **Both workflows were `success` at `f304bf383`, 2026-08-24T12:38.** ⚠️ That is **12 commits behind head** and does not cover them — and in this repo docs are build inputs for the acceptance rail, so a plan edit can redden CI. Re-derive rather than trusting this line:<br>`gh run list --repo atsign-foundation/at_client_sdk --branch gkc-pq-d1-spike --workflow at_client_sdk.yaml --limit 1 --json headSha,conclusion` (and the same for `at_libraries.yaml`), then `git rev-list --count <headSha>..HEAD`<br><br>⚠️ This row read "spike CI result unseen" until 2026-08-24, when the answer had been sitting there for hours | A dispatch against head, once the branch stops moving |
| ~~app enrollments cannot be PQ-native~~ **FIXED 2026-08-24** | ✅ **DONE — do not rebuild it.** `AtEnrollmentRequest` now **requires** `signingAlgo` on both constructors (no default, so the compiler enumerated all 22 call sites across 6 packages), and also forwards `advertisedSigningKey`, which the base class declared and neither constructor passed on. `mintApkamKeyPair` is shared with onboarding so the two cannot drift. A non-rsa2048 enrolment files typed material under the enrollment id once the atServer names it — the flat copy STAYS, because one enrollment named by the keyfile's own `enrollmentId` resolves the same either way, and clearing it breaks the approval handshake, which needs the keypair and the symmetric key from one `toAtChops`. ⚠️ **Three things the API change alone did not fix, each found by a failing run rather than by reading:** `enroll` did not forward `signingAlgo` to `sendEnrollRequest`, so the parameter would have existed and done nothing; `enrollmentKeyPackageBuilder` was never told the algorithm, though it has always taken one; and the approval handshake never set `signingAlgoType`, so an ML-DSA enrolment PKAM'd under at_lookup's rsa2048 default. **Proven at two layers**: `tests/at_functional_test/test/pq_native_app_enrollment_test.dart` (an mldsa65 enrolment keeps its id, an rsa2048 one still retrofits — the control) and `tests/at_onboarding_cli_functional_tests/test/pq_native_enroll_test.dart` against a real VE, where the assertion that matters is that the enrolment **authenticates**: PKAM is record-authoritative, so a client holding ML-DSA material can only authenticate if the atServer's record says ML-DSA. ⛔ **What is NOT covered, and is separate**: every other atServer implementation would record an ML-DSA enrollment and then never authenticate it. That gap is pre-existing, independent of this fix, and lives on an unmerged branch | Nothing. `--posture` now reaches the enrolment in `at_activate enroll`, defaulted once at the `enroll`/`sendEnrollRequest` boundary where a caller has no rollout position to read |
| doc-set reduction, phases 3–5 | ⛔ **RULED BY gkc 2026-08-23, AFTER D1 — do not start it while D1 is open.** The end state is five files: `roadmap.md` (stale, needs a pass), `design.md`, `acceptance.md`, `decisions.md` (seriously shrunk) and this plan, which from now records **only what is still owed**. Phases 1 and 2 landed 2026-08-23 — the rejections and measurements became [rulings 116 and 117](decisions.md), and this plan went 1,878 → 1,075 lines. **What remains, and phase 3 MUST precede phase 4:** (3) trim the **117** ruling bodies in `detail/decisions.md` and inline them into `decisions.md` — they average **98 lines each**, and only **4 of 116** rulings are dead, so this is an editorial pass over live content rather than a purge of obsolete ones; (4) delete `detail/` and repoint or remove the **250** links into it (113 from this file, 63 acceptance, 62 design, 9 roadmap, 2 decisions, 1 seal-spec), rewriting `docs_structure_test.dart`, which enforces index↔body correspondence both ways and names `detail` 28 times — the rail changes in the SAME commit or CI goes red; (5) substitute explanations for the code that cites `detail/` paths, which is a standing rule violation as well as a broken link: ⚠️ **this item shrank on 2026-08-24** — it named `pq_rollout_matrix_test.dart` and a dartdoc in `tests/pq_matrix/current/lib/envelope_exchange.dart`, and both files are now deleted along with the rollout matrix. The README was rewritten in the same change and cites `detail/` no longer, so **item (5) is discharged**. Measured 2026-08-24: only two code files still name `detail/`, and neither is item (5)'s — `cross_cutting_test.dart` reads `detail/decisions.md` as a build input and this row already exempts it, and `docs_structure_test.dart` is the rail item (4) rewrites. Re-derive before acting: `git grep --untracked -n 'detail/' -- tests packages | grep -v '\.md:'`. `cross_cutting_test.dart` reads `detail/decisions.md` as a build input and is fine. ⚠️ **Phase 3 is where this goes wrong silently** — a ruling trimmed too far reads complete, and 112 of 116 rulings are still in force. Re-derive the size: `for f in docs/projects/pq/*.md docs/projects/pq/detail/*.md; do echo "$(grep -c '' $f) $f"; done` | Nothing but D1 closing. `detail/` is **19,141 lines against 7,231 live**, so this is most of the reduction |
| arm 1 vs arm 3 bucketing | ⛔ **A RULING IS OWED FROM gkc, and it is not a research task** — the measuring is done. [`acceptance.md`'s "Which rows arm 1 owes"](../acceptance.md#which-rows-arm-1-owes) has both readings and the evidence; nothing here repeats them. In short: section 14's kind table says **3** transition rows, its arm-3 paragraph names **12**, and four rows — UC-B1.1, UC-B1.2, UC-B4.4, UC-A5.3 — are assigned to arm 1 and arm 3 at once, so the published "21 axis and consequence rows" double-counts. The two readings differ in what arm 1 *is*: under the count an arm-1 cell must drive a retrofit, so the arm stops being three static clients; under the prose a retrofit is an edge and belongs to arm 3. **Arm 1 as built sidesteps it** by covering only the 14 rows both derivations agree on, so nothing is blocked — but arm 3 cannot be scoped until this is settled, and the count table stays wrong until then | Nothing but the ruling. Arm 3 is the work it unblocks — arm 4 was cancelled 2026-08-24 |
| at_auth README | ⛔ **NOT a D1 gate.** ⚠️ This said it "should ride [PR #2179](https://github.com/atsign-foundation/at_client_sdk/pull/2179) with G1", and that home is gone — #2179 merged on 2026-08-25. It now lands wherever at_auth is next touched, still alongside G1 — `packages/at_auth/README.md` describes `FileAtKeysIo` at `:144` and `:191` and **never mentions `at_auth_io.dart`**. The barrel split is the single most consumer-visible change in 4.0.0 — a `dart:io` consumer has to add one import — and the CHANGELOG says so at length while the README says nothing. No code miscompiles from it (the README shows no import statements at all), which is why it is not a gate. Found by the wrap-up docs sweep 2026-08-23 | Nothing. One or two sentences where `FileAtKeysIo` is first named |
| **acceptance audit** | ⛔ **D1 GATE — the gap is established and the design is ruled ([115](decisions.md#115-the-acceptance-suite-is-4-arms-and-a-ledger-not-one-grid-2026-08-23)); what remains is the build** (gkc, 2026-08-23). **The rationale, in gkc's words:** *"we have literally hundreds of functional and end to end tests which cover the acceptance tests together. But there is no definitive place where it is easy to see the entirety of the pq project's acceptance tests being proven. The posture matrix test is the logical place to build test out."* So the problem is **legibility, not coverage**. Measured 2026-08-23, and **coverage was never the gap**: of the 68 live rows, 59 have live proof of some kind and 9 have none (12 LIVE_DIRECT, 43 LIVE_PARTIAL, 4 LIVE_INCIDENTAL, 9 NO_LIVE_PROOF). Only **29 of the 69** use-case ids are nameable anywhere in the live suite. ⚠️ **`tests/` holds 7 Dart packages** (⚠️ **6 since `tests/pq_matrix/current` was deleted** — corrected 2026-08-26 in the live plan) — the 4 live test packs plus `tests/pq_matrix/{current,published,scenario}`, the child processes the pair grid spawns. Count with `find tests -name pubspec.yaml`; a `tests/*/` glob returns 4 and reads as the whole answer. ⚠️ **The live corpus is 4 packs, not 2, and this row was scoped to 2 of them** — it read "**180** live test declarations across 65 files … a looser `grep -o 'test('` gives 225 and an indentation-anchored one 224". `tests/at_onboarding_cli_functional_tests` and `tests/at_onboarding_cli_functional_tests_proxy` are live packs as well, no citation reaches either, and the CLI one builds clients from a `PqPosture` in two arms — which makes it the best live evidence for UC-C1.6 and a second live proof of UC-A1.1. Across all 4 the strict matcher gives **194** and a multi-line-aware one **247**, and that gap is entirely declarations whose name sits on the next line, since an any-position same-line matcher also returns 194: `grep -rhoE "^[[:space:]]*test\([[:space:]]*'" tests/ --include='*.dart' | wc -l` against `perl -0777 -ne 'while (/(?<![A-Za-z0-9_])test\(\s*[\x27"]/gs){$n++} END{print "$n\n"}' $(find tests -name '*.dart')`. The posture matrix, the intended home, is **3** `test()` calls proving **2** use cases (UC-G1.14, UC-G1.15). ⚠️ **A citation count is not a coverage count** — an earlier pass here reported "27 of 68 have no live proof" when what it had measured was 27 with no live proof *cited from their acceptance scenario*. Do not restate it as coverage. For the record, the citation picture: of 68 scenarios, 2 cite the matrix, 39 cite some live test, 22 cite unit tests only, and 5 cite nothing and are themselves mock tests (UC-A3.1, UC-A3.4, UC-B3.1, UC-B3.2, UC-B5.2; UC-A3.1 runs against `MockAtClient()`). ⚠️ **And nothing checks the claims.** `catalogue_test.dart`'s five tests are all structural; none asks whether a scenario proves what its row asserts, and the `proves:` prose is matched against nothing ([14.19 item 29](implementation-plan.md#1419-small-items-raised-2026-08-12-and-not-yet-acted-on)). The one known overclaim, item 36's three clauses of UC-A2.5/UC-A2.6, was found by hand. **Steps (1) and (2) are DISCHARGED, 2026-08-23** — they read "(1) for each of the 68, find where it is *actually* exercised live — searching the packs, not just reading citations; (2) decide which are genuinely **posture-dependent**, since several of A3's self-data cases may not vary by posture at all". Both are answered in [ruling 115](decisions.md#115-the-acceptance-suite-is-4-arms-and-a-ledger-not-one-grid-2026-08-23), which carries the per-row map and the posture classification. gkc's A3 suspicion held: `PqPosture` declares 10 axes and only 7 vary across the stages, so 3 of the 5 A3 rows do not vary at all. **What is owed is step (3), and the shape is ruled rather than open**: only **3** of the 68 rows are shaped like a grid cell and **38** do not vary by posture, so the target is **4 arms and a generated ledger** — a 3-cell stage arm, the existing 4×4 pair grid, a transition arm for the edges the catalogue is full of, and a server-version arm — with 4 prerequisites named in the ruling, **2 of them now discharged**. ✅ This row said the sharpest was that "this pack has no `dart_test.yaml` and no `pq` tag (0 hits, against 9 in the e2e pack)" — built 2026-08-23: the tag is declared and 35 of its 55 test files carry it, chosen by the mechanisms they drive rather than their names, and `test/pq_tag_test.dart` re-derives the set so a new PQ test cannot sit outside it. ⛔ No `paths:` allowlist, deliberately — this pack's virtualenv is thrown away per run, so allowlisting would take the e2e pack's silent-omission risk with none of its benefit. ⚠️ **A fifth prerequisite was listed here and is now measured away**: this row said `PqPosture.pqActive` "currently breaks the monitor (`nskey_self_notify_live_test.dart:289`)". It does not. Equal-length interleaved arms across 2 fresh virtualenvs gave pqActive **16 of 18** monitors received against a control's **18 of 20**, with the atServer's log carrying `signingAlgo:mldsa65` authentications — both arms fail at the same rate with `AT0014`, so the failure is real but is **not posture-dependent**, and a pqActive cell is no worse off than a legacy one. ✅ **The ledger half of step (3) is BUILT, 2026-08-23** — `tool/acceptance_ledger.dart` plus the recording in `provenIn` and report emission in all three `runLocal.sh` runners; rendered from a real CI run's artefacts across both workflows the catalogue reads **63 PROVEN · 0 NOT-EXERCISED · 6 NO-LIVE-CITATION** across 69 rows (2026-08-23). ⚠️ This said “over all four report sources … **62 PROVEN · 1 NOT-EXERCISED** … the one gap being UC-B0.1's tagged legacy-server job”, which was a LOCAL render — UC-B0.1 is exactly the row a local run cannot reach and CI can, so the gap was in the runs supplied rather than in the coverage. ⛔ **It did NOT need `manifest.dart` moved**, which this row and ruling 115 both listed as its prerequisite. ✅ **Arm 1 is BUILT (2026-08-23)** — `tests/at_functional_test/test/pq_stage_arm_test.dart`, three enrollments of one atSign at one posture each, functional pack **186/186**, and **UC-C1.2 executed live for the first time**. It covers the 14 rows both derivations of the arm-1 set agree on rather than the contested 21 (see the `arm 1 vs arm 3 bucketing` row above), and it does **not** measure UC-C1.4, since `enrolAndAuthenticate` builds pq-mode enrollments only and every cell therefore holds `keyExchangeMode` constant. ✅ **Arms 2 and 3 are BUILT (2026-08-24)** — `tests/at_functional_test/test/pq_posture_grid_test.dart` is the grid (sender posture × receiver readiness, 9 enrollments over 2 atSigns, 7 `test()` calls) and `tests/at_functional_test/test/pq_advance_ladder_test.dart` is the ladder; `tests/pq_matrix/` was cut to `published/` and `scenario/`, which `tests/at_functional_test/test/pq_released_peer_test.dart` spawns to keep UC-G1.14 proven. **What step (3) still owes:** this clause read "**arms 2 and 3**", and before that "arms 2–4" until gkc cancelled arm 4 on 2026-08-24; the design of arms 2 and 3 was ruled the same day ([acceptance.md section 14](../acceptance.md#the-arms)). ✅ **The clause level is BUILT (2026-08-24)** — ⚠️ this read "What is left is **the clause level** of the ledger, which is the half that does touch the live tests and is what turns "UC-A2.5 has 3 unproven clauses" into a computed fact rather than a footnote". It is now that computed fact: `clauses:` on `provenIn` pins a citation's THEN clauses by distinctive fragment (a fragment matching none or two is an error), `tool/acceptance_ledger.dart` renders the checklist, and `docs_structure_test.dart` guards the parser so a prose reformat cannot silently reduce every row to 0/0. Measured on the first render: **129 clauses across 68 live rows**, 7 pinned by a proven citation, UC-A2.4 **5 of 6** with the `pqSeal ver 0x03` clause uncovered, UC-A2.6 **0 of 3** with the revoked-E4 state gate confirmed absent from the cited live test (`grep -ci revoke` on it returns 0 against 53 for `enroll`). ⛔ It did NOT need `manifest.dart` moved to `lib/`. What is left is **the CI combining job**, left unwired because it needs `actions/download-artifact` and neither this repo nor at_server carries a trusted pin for it — CI uploads the inputs and rendering is local, which is now one command (`tools/acceptance_ledger.sh`) rather than the four hand-assembled ones this row's "rendered on demand" implied. ✅ **Two further gaps gkc named on 2026-08-23, both now BUILT.** They were: (a) nothing in the tree invoked the renderer — `git grep -P "dart\s+run\s+\S*acceptance_ledger"` returned exactly one hit, the usage comment inside the tool itself, so every ledger so far was assembled by hand from a scratch directory; and (b) nothing guarded the population wiring, with **0** tests reading `.github/workflows/` (positive control: the path string appears in 5 non-test files) and none reading the three `runLocal.sh`. What landed: **`tools/acceptance_ledger.sh`**, one command that runs the unit sources, optionally the live packs (`--with-live`), and renders; and **`packages/at_client/test/acceptance_ledger_wiring_test.dart`**, which asserts each of the four emitting jobs still carries its flag, that `unit_at_client` still sets `ACCEPTANCE_LEDGER`, that every emitter uploads with `always()`, and that each runner still gates the reporter on `ACCEPTANCE_REPORT`. ⚠️ **The rail's first version had a hole worth recording**: it asserted `contains('ACCEPTANCE_REPORT')` and `contains('--file-reporter json:')` separately, and a mutation making the guard read a *different* variable left both satisfied — the variable is named three times in each runner, so severing the coupling changed no substring. It now pins the coupling itself (`-n "${ACCEPTANCE_REPORT:-}"` and `--file-reporter json:${ACCEPTANCE_REPORT}`), which is the same weakness this section already records in `provenIn`, reproduced one layer up. Six mutations, each reddening its own assertion. ⚠️ **`provenIn` APPENDS to its citations file**, so two runs against one path double every citation and the ledger reports 278 for a catalogue of 139 — the driver deletes it rather than trusting the caller. **Re-derive**: `grep -rho 'UC-[ABCG][0-9]*\.[0-9]*[a-z]*' tests/at_functional_test/test tests/at_end2end_test/test | sort -u | wc -l` against the 69 in `acceptance.md` | Nothing |
| [14.43](implementation-plan.md#1443-the-functional-suites-convergence-race) residue | ⛔ **NOT D1, and NOT PQ (gkc, 2026-08-23)** — recorded here only because this project has no other checked-in owed-work list. The behaviour is in `sync_service_impl.dart`, i.e. at_client's general sync, and no use case asserts sync ordering. The test-side fix landed in `ccf4987a4`. **A sync pull applies an OLDER server entry over NEWER local state** — the pull-side face of the versioning shape C fixed on the push side. Recorded when 14.43 closed and not designed since. Also open from that section: a driver-side `expect` failure on a protocol-green cell still dumps nothing | Nothing. The section carries the discriminators for any future red of the family |
| [14.45](implementation-plan.md#1445-an-expired-key-the-client-cannot-delete-pins-it-in-a-hot-loop) residue | ⚠️ **In another repo: `at_persistence_secondary_server`.** Its keystore `get()` does not filter expired records, which is what let an expired key be read back and re-swept. Named here because this is where the work that found it lives; it does not land here | Separately owned. Not a D1 gate |
| [14.50](../implementation-plan.md#1450-the-e2e-teardown-revokes-enrollments-belonging-to-other-runs) | ⛔ **NOT a D1 gate (gkc, 2026-08-23)** — e2e runs isolate locally and are serialized by structure on GitHub. ⚠️ Recorded because a reader will re-derive it: there is no top-level `concurrency:` key in any workflow, so `needs:` serializes the e2e jobs *within* a run and not across runs, and the incident that produced this row was cross-run. Stays as unblocked hygiene. **The e2e teardown revokes enrollments belonging to other runs.** `tests/at_end2end_test/test/enrollment_teardown.dart` revokes every approved enrollment on the shared `@ce2e1`-`@ce2e4` atSigns with `force: true`, not only the ones its own run created, so two overlapping CI runs tear down each other. **Diagnosed 2026-08-22** from the *other* run's log - the section carries the two timestamps 430 ms apart and the shared enrollment id. This row read *undiagnosed, and the newest CI run is red* until then. CI has since been green three times — 24/24 twice and 47/47 on [PR #2179](https://github.com/atsign-foundation/at_client_sdk/pull/2179) — but every one of those windows was free of another run, so that is a rate and not a fix. Owed: a run-unique marker, so a teardown revokes only what its own run made | Nothing. Needs no permission and no publish, and it does not gate the at_auth carve |
| [14.18](../implementation-plan.md#1418-the-remaining-d1-initial-development-sequence) | ⛔ **THIS IS D1's CRITICAL PATH** — D1 ends when the acceptance set passes and every rail is green, and the remaining carves and publishes are what gets there. Steps 32–34: the per-package release train. at_commons #2168, at_chops #2169, at_lookup #2174, at_server_status #2177/#2178 and **at_auth [#2179](https://github.com/atsign-foundation/at_client_sdk/pull/2179) — merged 2026-08-25 as `09fc94d28`** are all **merged to trunk**, so **six of eight positions are through by merge**. ⚠️ This read "at_auth is #2179, **open with CI 47/47 green**". Remaining to carve: **at_client, at_client_flutter, at_onboarding_cli**. Re-derive the whole picture rather than reading this cell — for each package compare `pubspec.yaml` on trunk, on this branch, and `curl -s https://pub.dev/api/packages/<pkg> \| python3 -c "import sys,json;print([v['version'] for v in json.load(sys.stdin)['versions']][-5:])"`. ⚠️ **Measured 2026-08-22 with a command that could not see a prerelease**, and it read "pub.dev has … at_lookup **3.6.1**, at_server_status **1.1.1**". Re-measured 2026-08-24 against the versions list: pub.dev has at_commons 5.16.0, at_chops 3.6.0, **at_lookup 3.7.0-rc1**, **at_server_status 1.1.2-rc1**, at_auth 3.3.0, at_client 3.14.0 | ⚠️ **Merged is not published, and only the publishes still gate anything.** ⚠️ This said at_lookup 3.7.0-rc1 and at_server_status 1.1.2-rc1 were "on trunk and **not on pub.dev**"; both were published by 2026-08-24, so the live gate is now **at_auth 4.0.0-rc1**. Every later package can carve and merge but none can publish until gkc publishes those. ⛔ **This cell used to say the at_auth PR's CI would fail to resolve until at_lookup published. That was wrong** — a pub workspace resolves siblings by path, so #2179 resolved and went green with at_lookup unpublished; the gate is on publishing, never on carving or merging. ✅ **at_client's `at_commons` floor is FIXED, 2026-08-25** — it read `^5.15.0` while `notify_request_transformer.dart:154` calls `metadata.copy()`, which is **absent from at_commons 5.15.0 and present in 5.16.0**, checked against the published packages in `~/.pub-cache` rather than against the changelog. It now declares `^5.16.0`. ⚠️ **One floor is not the sweep this cell asks for**: every other constraint at_client declares is still unchecked against first use, and the same question applies to at_client_flutter and at_onboarding_cli before they carve. ⚠️ **Owed at the real release, and it belongs to this row because it is the train's:** every constraint moved to an `-rc1` floor reverts to its stable form when these publish, or a stable release ships requiring a candidate. The rule is in [14.49.2](implementation-plan.md#14492-every-remaining-package-publishes-as-a-release-candidate); re-derive the sites — `git grep -n 'rc1' -- 'packages/*/pubspec.yaml' 'tests/*/pubspec.yaml'` |
| [14.18](../implementation-plan.md#1418-the-remaining-d1-initial-development-sequence) | **Step 20's rotation arm — STAYS IN D1** (gkc, 2026-08-23), which is why D1 now ends past the carve. Chain: publish at_auth 4.0.0 → add the `pending` value → build the arm | The publish, and a dedicated CRAM atSign. ⛔ **The "wait for the fleet" gate is CLOSED** — the two keyfile formats are disjoint for every file that exists (3.3.0 dispatches on `version` and never reaches its `keys` parse without one; a 4.0.0 typed document emits `version: 1` and no `keys`), and the one reachable conflict needs a 4.0.0 typed write into a keyfile a 3.3.0 app also opens, which cannot have happened: **no production `.atKeys` or keychain entry holds any PQ key material** (gkc, 2026-08-23) |
| [14.19](../implementation-plan.md#1419-small-items-raised-2026-08-12-and-not-yet-acted-on) | ✅ **Item 36 — the one D1 gate here — is CLOSED 2026-08-24.** All three clauses are live-proven in `key_package_amendment_live_test.dart` and pinned so the ledger counts them; two of the three corrected the catalogue's own wording (there is no revocation check inside `enroll:update`, and an amendment joins rather than supersedes). ⚠️ This read "**TRIAGED 2026-08-23: only item 36 is a D1 gate**, and it is the one known case of the catalogue asserting clauses no live row proves" — it was, and it no longer is. Of the rest, three are not work at all (20, 21, 26 — each says so in its own text) and two belong elsewhere (14 is not PQ, 35 lands in `atGettingStarted`), leaving six that are open and not D1: 2, 4, 10, 28, 29, 34. Items 8, 23 and 30 were settled the same day. The headline count below overstates the work, which is why it keeps being re-argued — **17** open small items of 36 — the items are in `detail/`, none of them blocking. Re-derive rather than quoting: this row said 17 while the count was 10, then 15 while the count was 18, and the comment beside the command said 17 for two days after the row was fixed | Item 8 is the only one waiting on a ruling. Items 20 and 21 are examined-and-left, not work. Item 35 lands in `atGettingStarted`, not here |
| S-5 residual | ⛔ **POST-D1 CLEAN-UP, not a D1 gate** (gkc, 2026-08-23). ⚠️ **This row read "D1 GATE, and it lands on [PR #2179](https://github.com/atsign-foundation/at_client_sdk/pull/2179) while that is open" earlier the same day**, and the PR-#2179 window no longer constrains it — after D1 that PR will be long merged, so the test goes wherever `RegistrarService` then lives. It is `G1` in [THE NEXT MOVE](#15-the-lettered-d1-gates-g0g8-as-they-were-discharged), below the gates rather than at the top of them. Everything below is the harness, kept intact for whoever picks it up. **The registrar's switch to validating TLS certificates is untested, here and in CI.** `RegistrarService`'s default client used to accept ANY certificate - `badCertificateCallback` returning true unconditionally, on calls carrying the registrar API key. It is now a plain `package:http` client that validates, with the bypass behind `RegistrarIoClient.allowBadCertificates`, off by default and shouted when used. **Neither arm has a test**, and CI cannot catch a regression: `RegistrarIoClient` appears in ZERO CI job logs (control: `RegistrarService` appears), and `RegistrarIoClient.create()` has **no in-tree caller at all** - it is a public opt-in for consumers, which is deliberate, so do not delete it as dead code. Owed: a test pinning both arms against a self-signed local server. ⚠️ **Attempted and parked 2026-08-22**, so the next reader does not start cold: the shape works — mint a cert at test time with `openssl req -x509 -newkey rsa:2048 -nodes -subj /CN=localhost`, serve it with `HttpServer.bindSecure`, and point `RegistrarService` at `localhost:<port>`, which `Uri.https` accepts as an authority. Three arms, and the third is the positive control that proves the server is up: the default client refuses, `RegistrarIoClient.create()` with the flag off refuses, and with it on succeeds — without that third arm a refusal is indistinguishable from a server that never started, because `package:http` wraps connection-refused in the same `ClientException`. ⛔ **Do not commit a PEM fixture** — GitHub push protection can block a private key; mint it in `setUpAll`. | Nothing |
| [14.16](implementation-plan.md#1416-four-residuals-the-issue-tree-audit-surfaced-2026-08-09) | ⛔ **STEP 29 LEAVES D1 — all four dispositioned 2026-08-23.** ① perf ceiling on real low-end hardware → post-D1 cleanup (#2153). ② UC-A3.4 → done 2026-08-17. ③ SS-4 resume → **ruled NO RESUME** (the election makes republishing a filed pair a regression) and **re-filed as orphan growth**: `store()` calls `addKey`, nothing in `crypto/nskey/` retires a filed private, so every abandoned mint — crash or the designed lease-expiry abandon — permanently adds key material to the user's `.atKeys`. ④ IS-1 drift → not D1; at_server #2683 is open, untouched since 2026-08-06, and already ruled to be pared back | Only ③'s orphan-growth half is owed here, and it is a decision before it is code |
| [14.12](../implementation-plan.md#1412-a-mintlegacymaterialfalse-atsign-cannot-write-a-public-record) | ⛔ **NOT D1 (gkc, 2026-08-23) — it gates the post-R-2 stop-release.** A `mintLegacyMaterial:false` atSign cannot write a public record. Out of D1 because both moves it needs are B-3 phase 1, which is parked, and nothing about it blocks the carve; the live assertion in `pq_legacy_interop_live_test.dart` keeps it pinned and the flag must still not be recommended | Two moves its body names, neither scheduled: public-record signing onto the ML-DSA signing root, and self data off `selfEncryptionKey` onto the nskey path (B-3 phase 1). ⚠️ This cell read "Gates the stop-release" until 2026-08-18 — which is what 14.12 *blocks*, so anyone scanning this column for what is ready to start misread the row as ready |
| [14.42](../implementation-plan.md#1442-why-enrollment-setup-takes-four-minutes) | **Why `enrollment_setup.dart` takes ~4 minutes.** Measured at 3:56 and 4:59 against the @ce2e atSigns; 30 seconds is nowhere near enough and the budget is now 15 minutes, which hides rather than explains it. gkc asked for the cause, 2026-08-20 — **not a D1 gate (2026-08-23), but owed to him rather than plan-generated hygiene, so do not quietly demote it.** ⚠️ **What this row still lacks is the thing that would let anyone start:** how to obtain `config14.yaml` and the `@ce2e` keyfiles locally. Until that is written down, the only route is a CI round trip. ⚠️ My sync-backlog reading is NOT established — `end2end_tests` runs the same four atSigns and the same suite in ~3 minutes | ⛔ **@ce2e-only — it does NOT reproduce locally, and this cell said it did.** `runLocal.sh` regenerates `config/config.yaml` from at_demo_data, and against demo atSigns the same four enrollments take about ONE SECOND — a local run reproduces the symptom's ABSENCE. The ~3-minute local repro belonged to a DIFFERENT and already-fixed defect (14.41 row 3's cache key). Reaching this one needs `config14.yaml` and the @ce2e keyfiles, i.e. a CI round trip, and nothing here records how to get those locally |
| [14.47](../implementation-plan.md#1447-the-at_client-unit-tree-has-a-cross-file-isolation-flake) | **NOT a D1 gate (gkc, 2026-08-23) — hygiene.** It is green alone and green in the full suite, and reddens only in one hand-constructed non-alphabetical ordering that nothing actually runs, so no rail as invoked is at risk. Keep the reproduction recipe. **A unit-tree isolation flake**: `local_secondary_sync_queue_test.dart` failed 1-in-4 when run after the nskey/pq files in one non-alphabetical invocation — a same-file test's queue entry leaked into a later test, so the per-test store isn't always fresh. Green alone, green in the full suite | Reproduce at rate (~10 runs of the four-file order), then read the file's setUp for what makes the store per-test fresh |
| [14.46](../implementation-plan.md#1446-executeverbs-sync-parameter-is-inert-on-both-secondaries) | **`executeVerb`'s `sync` parameter does nothing** — declared, never read, on at_client's both secondaries AND at_lookup. **Decided and phase 1 shipped 2026-08-20**: `@Deprecated` on all six declarations for 3.x, removal in 4.0; every cross-package and every prose-reasoned call site cleaned. ⛔ **NOT D1 (gkc, 2026-08-23)** — the removal rides at_client/at_lookup **4.0**, and nothing in the acceptance set asserts the parameter (its one catalogue mention is prose about a mock). Still in the section: a stale at_server comment #2169 will falsify, which lands in a sibling repo | **Removal at 4.0** — delete the parameter from all six declarations and let the compiler enumerate the ~76 remaining same-package sites |
| [14.44](../implementation-plan.md#1444-residuals-from-the-at_chops-pr-review) | Residuals from the at_chops PR review. ✅ **The first is DONE 2026-08-22**, in the at_auth carve as this row said it should be — `encode` refuses an `ArgonHashParams` whose `hashLength` is not the value `decode` will use, which was the section's own preferred option over persisting it. **Two remain:** `XWingCore.combine` writes at hardcoded 32-byte offsets while sizing its buffer from actual lengths — ⛔ **both remaining residuals are POST-D1 (gkc, 2026-08-23)**, and the severity is worth recording: it is **correct for X-Wing**, whose four inputs are all 32 bytes, and **latent and silent** otherwise, because `setRange(0, 32, …)` takes the first 32 bytes of a longer input without error and yields a well-formed but wrong digest; and at_chops 3.6.0's CHANGELOG owes the resolution-skew sentence whose durable record is ruling 110's addendum | Nothing. Both remaining ones go whenever at_chops is next open |
| [14.11](../implementation-plan.md#1411-deprecated_member_use-findings-across-the-workspace) | **STAYS IN D1, with the bucket-B migration** (gkc, 2026-08-23). Re-measured 2026-08-23: **754** findings — at_client 396, at_onboarding_cli 205, at_auth 153, at_lookup **0** (the section's table now carries both columns — the 2026-08-18 figures and these, so it needs no further update). Five buckets, and only **B** has a replacement that exists today: 71 credential-ladder uses (`enrollmentId` 59, `signingAlgoType` 12) moving onto the `AtAuthenticator` seam at_lookup 3.7.0 ships — **24 sites in `lib/`, 47 in tests**. A (AtChops compatibility API, 530) and C (legacy flat keyfile fields, 118) are transient and get **no ignores yet**; D (27) is at v5 | Nothing. Every package exits 0, so none of this blocks a carve |
| [14.34](#1434-an-unexplained-intermittent-in-self_enrollment_retrofit_live_testdart) | ⛔ **D1 GATE (gkc, 2026-08-23).** `self_enrollment_retrofit_live_test.dart` failed **once in five** pack runs. D1 now ends when every rail is green, and an unexplained live failure at that rate makes "green" a rate rather than a state — so it has to be understood before D1 closes | Unexplained. Not a flake and not fixed — a rate, not a kind |
| [14.29](../implementation-plan.md#1429-the-residuals-1425-surfaced) | ⛔ **NOT D1 (2026-08-23)** — the section's own text says none of these blocks D1's remaining sequence, and SS-2's `__ssenv` half is explicitly *deferred, not owed*: the 2026-08-03 ruling took DEP4 off SS-2 and what is left is a pure optimisation. SS-2's `__ssenv` and two small S-3 items — none blocking. Re-read 2026-08-18: B-1's residuals had shipped and S-3's migration test existed, so this row said **three B-1 residuals, three small S-3 items** against an actual none and two | — |
| [14.39](../implementation-plan.md#1439-pqposture-and-the-rollout-it-drives) | `PqPosture` — **mostly DONE 2026-08-19**: the rename, the 3 postures, the posture-only refusal flag, the sender-side algorithm list and the CLI's `--posture` all shipped, live-green. **Client-driven retrofit at start is BUILT 2026-08-19**, sequenced into `_init` rather than re-pointing a live client; unit-green and **live-green** — functional 174/174 (after one 173/174 whose single failure was [14.34](#1434-an-unexplained-intermittent-in-self_enrollment_retrofit_live_testdart)), e2e pq 54/54, and the `legacy-server` arm 2/2 against the pinned `atsigncompany/virtualenv:vip-p3.15.0`. **Owed: public-data signature verification** (undesigned) — ⛔ **POST-D1, and deliberately NOT in the acceptance catalogue (gkc, 2026-08-23)**: `dataSignature` appears zero times in `acceptance.md`, against 28 mentions of "signature" as a control, so nothing asserts it. ⚠️ Worth stating plainly since it reads as an omission otherwise: `pqActive` already **signs** public data and nothing anywhere verifies it — not at_client, not the atServer — so we emit a signature no one checks, knowingly | Nothing |
