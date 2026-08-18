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
     R-2 at_client 4.0 (apply the postQuantum posture defaults — five axes, decisions 70) — final; NO CLIENT-SIDE WORK OUTSTANDING as of 2026-08-17, gated on the ecosystem floor alone (see 14.33)
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

### S-1 — at_auth: extend `AtKeys` in place (additive PQ methods, deprecate legacy) + `AtKeysIo` runtime persistence (API only); publish 3.3.0 · at_auth · M — **SATISFIED and PUBLISHED — at_auth 3.3.0 is on pub.dev (re-verified 2026-08-08); no residual.** Consequence: **at_auth 3.4.0 is already open** in-tree and unpublished (opened 2026-08-03, `936241d8f`), so a further at_auth change folds into that heading rather than opening a new one
**Goal:** extend the existing `AtKeys` in place so it holds every key (per-enrollment AND per-APKAM) via
additive PQ-safe accessors while the legacy key fields deprecate; interface-first.
**Builds on:** at_auth `AtKeys`. Additive only; gates nothing in Wave 2.
**Deliverables → [design.md](../design.md)** (structural design: extend `AtKeys`/`AtKeysIo` in place): keep the
`AtKeys` class hierarchy as-is and extend it **additively** with PQ-safe methods (`addKey`/`retireKey` over
typed `AtKeysMaterial`; **retire, never remove** — forward-only status, 2026-07-17 ruling), **deprecating**
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
`keyPartType`/`keyAlgorithmType` tokens round-trip unmodified.
**Effort:** M.
**Watch-outs:** ⚠️ **version** — resolved 2026-07-17: at_auth 3.1.1 published, then **3.2.0 was consumed by
the validateAtServer network-timeout release**; S-1 ships as **3.3.0** (Open decision #D closed). The
at_chops 3.4.x prerequisite (hashing-algo barrel exports) is satisfied — 3.4.0 published 2026-07-17.
**Publish state:** S-1 landed via PR #2047 (+ #2080 tweaks). **`at_auth 3.3.0` is published stable on
pub.dev** — the old rc1 → stable gate is **closed**, so S-6 (consumer bumps) and SS-2's at_auth work have
the stable version they needed to pin against. **at_auth 3.4.0 is open in-tree and unpublished**
(`936241d8f`, 2026-08-03) carrying `KeyAlgorithmType.mlKem1024` and the `.atKeys` passphrase-salt fix, so
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

### S-5 — at_auth 4.0.0: WASM barrel split · at_auth · L  *(parallel, off the GA critical path)*
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

### S-6 — Consumer constraint bumps onto at_auth `^4.0.0` · at_client, at_onboarding_cli, at_client_flutter, **tests/at_functional_test, tests/at_end2end_test** · M
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
`AtEnrollmentRequest.metadataBuilder` in at_auth 3.4.0. Still to do: build and sign the key
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
| **D1 GA critical path, re-derived 2026-08-04 against pub.dev and the skip counts.** Complete: P-*, S-1/S-2, SS-1a/1b/1c, **SS-2**, **SS-3**, **SS-4** (bar key transparency, parked), **B-1** incl. all chunks. Remaining on the GA path: **R-1** (L, migration machinery + `disallowLegacyEncryption` + strict mode), **B-2** (L, nskey rotation + revocation), **ON-1** (M, PQ-native greenfield onboarding), **R-2** (M, the 4.0.0 flag flip), and **S-3** (L, updatable `.atKeys`/keychain). Off the GA path: the **RF-\*** retrofit trio. Referenced only: D2-1. Separate track: IS-1. Publish gates verified against pub.dev the same day — at_client 3.14.1/3.14.0, at_commons 5.14.0/5.13.0, at_chops 3.4.2/3.4.1, at_auth 3.4.0/3.3.0 (so the old at_auth `3.3.0-rc1`→stable gate is **closed**). ⚠️ **Re-verified 2026-08-11, and two of these moved:** in-tree/published is now at_chops **3.6.0**/3.5.0 and at_commons **5.15.0**/5.14.0 | plan |
| **`at_auth` 3.4.0 is open and unpublished**, and at_client now depends on `AtEnrollmentRequest.metadataBuilder`. Same masking as the at_commons row below: workspace resolution hides it, so a green build says nothing | `at_auth` |
| ~~`at_end2end_test` has not been run since at_auth's surface changed~~ — **run 2026-08-04, green at 41 with no skips**, the same count as 2026-08-03. So neither at_auth's added surface (`EnrollmentKeyExchangeMode`, `apkamSymmetricKeyResolver`, `approvedWithMintedKey`, the grown `AtEnrollmentResponse`/`EnrollmentRequestDecision`) nor the arrival-path work regressed it — the latter mattering because that commit added work to `AtClientImpl`'s init, which every e2e test drives. All four rails now verified together: `at_client` 825/39 skipped, functional 113, e2e 43, `at_client_flutter` analyze clean | `at_end2end_test` |
| ~~`NskeyPrivateFiling.start` is an arrival hook nothing calls~~ — **fixed 2026-08-04, and it was three defects rather than one.** The prescription recorded here — give the nskey path `PqSigningRoot.filePendingPrivate`'s store-check treatment — would have produced a second method that looks right and files nothing, because the model it was told to copy had the same defect one layer down. `SecretStore` is an in-memory map whose only populator is `PairwiseSecretSharing.sweepOnce`, and **no production code in `at_client` ever called `sweepOnce` or `startListening`** — so at client start that store is empty and the root private was never filed either. One layer lower again: `KeyPackageRegistration.register()` mints a fresh X-Wing keypair per process (`loadApkamKeys` was wired only in tests), so the running client's `kpid` was never the one its enrollment advertised and a sweep would have scanned an address nobody writes to. `collectConveyedKeyMaterial` closes all three in order — bind the key package to `AtKeys`, sweep remote, then file — and `NskeyPrivateFiling.filePending` replaces `start`/`stop`. Live-covered in `conveyed_key_collection_test.dart`, with both defects reinstated as negative controls: disabling the binding fails the kpid assertion, disabling the sweep fails both tests | `at_client` |
| ~~**The substrate's unit fixture cannot see routing** — one map backs local storage and the atServer, so a local-first write and a remote-first one are indistinguishable by results. Routing is asserted directly instead (`putOptions`, `scanRoutedRemote`). Closing it properly means modelling sync in the fixture~~ — ✅ **CLOSED 2026-08-16.** `buildRemoteBackedMockClient` takes an optional `localData`; supply it and the two stores diverge exactly as a device's do — a local-first write lands only locally until `syncToRemote`, and a local-first read of a key only the atServer holds **misses**. Divergence is opt-in because the nine callers that predate it assert routing directly and specify the default. Proven by mutation in `remote_backed_client_routing_test.dart`: making local reads fall through to remote turns the peer-write row red | `at_client` tests |
| **`at_client` cannot publish until `at_commons` 5.15.0 and `at_chops` 3.6.0 do.** ⚠️ **Restated 2026-08-11:** the floors this row used to name — `^5.14.0` and `^3.5.0` — are now *published* numbers holding *other* content, because trunk released both while the spike claimed them. at_client's floors are `^5.15.0` and `^3.6.0`, and neither is on pub.dev. Checking pub.dev for 5.14.0/3.5.0 and finding them live is the trap this row now exists to prevent. Workspace resolution masks the gap exactly as the publish-ordering caution warns, so a green build says nothing | `at_commons` / `at_chops` |
| ~~The secret-sharing substrate has no live coverage in either pack~~ — **opened, not closed.** `secret_sharing_delivery_test.dart` now drives it live: the envelope is on the atServer by the time `sendEnvelope` returns, and a client that has never synced fetches and decrypts it from there. Both fail against the pre-fix build and nothing else does, so they detect the defect rather than merely passing. **Still owed:** everything beyond envelope delivery — `pushSecretToNamespaceMembers`, the `requestSecret`/`waitForSecret` pull flow, and anything needing two real enrollments, which waits on SS-2 | `at_functional_test` |
| ~~**The substrate's unit fixture backs local storage and the atServer with one map**, so it cannot see a local-first-vs-remote-first defect on the read side at all — which is how the `__ssenv` wake-up ordering bug survived. Fixed for the write side by asserting the put's routing directly and for the sweep by asserting the scan's, but the blind spot itself remains: any future substrate read that depends on routing is untested unless someone remembers to assert the routing rather than the result. Closing it properly means modelling sync in the fixture, so local and remote diverge and a wrong route fails on its results. The live pack now covers the two paths that matter today~~ — ✅ **CLOSED 2026-08-16.** `buildRemoteBackedMockClient` takes an optional `localData`; supply it and the two stores diverge exactly as a device's do — a local-first write lands only locally until `syncToRemote`, and a local-first read of a key only the atServer holds **misses**. Divergence is opt-in because the nine callers that predate it assert routing directly and specify the default. Proven by mutation in `remote_backed_client_routing_test.dart`: making local reads fall through to remote turns the peer-write row red | `at_client` tests |
| ~~Real nskey minting + per-APKAM conveyance~~ — **done.** `mintAndPublish` takes a remote-first immutable `_nskeylock`, files the private into `AtKeys` **before** publishing, and publishes nothing at all if it cannot. `NskeySeeding` mints at client init across a client's authorised namespaces and conveys every held generation, reading from `AtKeys` rather than the in-memory store. `InMemoryNskeyKeyRing` remains for tests only | **SS-4** |
| ~~**Mint** of `public:pq_signing_root@<atSign>`~~ — **done, and so is its conveyance.** `PqSigningRoot` mints immutable create-once with the private filed before publish; the private is conveyed to fully privileged enrollments at approval under a per-enrollment name, filed into `AtKeys` at start, and `PqSigningChain.publishOwnRootLink` anchors the holder to it at mint and at every start. Live-covered end to end, including that the atServer really does grant `*` + `__manage` — without which the privilege gate would have been tested against two identical cases | **SS-4** |
| ~~Wire the nskey `CryptoConfig` at init~~ — **done 2026-08-04** ([decisions.md 27](decisions.md#27-the-era-default-read-the-new-scheme-everywhere-write-it-once-2026-08-04)). Not by adopting `CryptoConfig.nskey`, which sets the AES-GCM path as the *write* default and is therefore the 4.x shape: final 3.x reads PQ and still writes legacy, so `CryptoConfig.readsNskeyWritesLegacy` registers the same provider set with `defaultProviderId` left at `legacy`. `forClient` stopped being a constant — the providers hold per-atSign state, so the set is built once per client at init and looked up, via an `Expando` rather than written into the shared preference object. The era ring gets the client's `AtKeys` as its `privateFiling`, without which it would see only what this process minted. Live-covered end to end by `era_default_read_test.dart`: **bob, given no `CryptoConfig` at all**, opens a record alice sealed to his namespace key, with alice opting in to `CryptoConfig.nskey` to write PQ — the asymmetry as an executable statement. (An owed item claiming the era ring was unreachable from a test was recorded and then withdrawn the same day: `NskeyProvider.keyRing` is public and exported, so it always was.) | **SS-4** |
| ~~`AtClientPreference.crypto` signals "app named nothing"~~ — **done; reshaped 2026-08-09** ([decisions.md 56.7](decisions.md#567-the-two-published-api-breaks-are-repaired-not-shipped)). The signal was briefly a nullable type; that broke the published non-nullable field, so it is now the distinguished `const CryptoConfig.eraDefault()` marker as the field's default — same meaning ("whatever this release encrypts with"), published surface intact. Every reader goes through `CryptoConfig.forClient(atClient)` — the one place the era default lives. The SDK deliberately does *not* resolve into the app's preference object: harmless while the default is a const, a per-atSign leak the moment it is not. What SS-4 still owes is the *other* half — building the key ring at init once the default becomes the nskey path | **SS-4** |
| ~~The `_nskeylock` mint/rotate race~~ — **done.** `NskeyMintLock` takes it remote-first, because the atomicity is the atServer refusing a second immutable create; a local-first put would let both enrollments believe they won and collide only at sync. The loser re-reads and adopts rather than waiting | **SS-4** |
| ~~The bench harness `acceptance.md` says lands with B-1~~ — **built 2026-08-04**, `packages/at_client/benchmark/crypto_bench.dart`. Reports three **separately-based** groups and refuses to combine them: *per record* (what every put/get pays once a CK exists — AES-256-GCM vs the legacy AES-256-CTR path), *per (owner, namespace) conveyance* (where PQ actually costs something — X-Wing `pqSeal`/`pqOpen` vs RSA-2048 wrap, paid **once** and then covering every record in scope), and *per authentication* (the ML-DSA-65 ↔ RSA-2048 signature swap). Mixing them is what would produce a headline "PQ is N% slower" from incomparable denominators. **The desktop baseline is now recorded** in [decisions 28](decisions.md#28-the-pq-performance-budget-measured-2026-08-04) — the harness had been run when it was built, but its numbers were never written down, so the acceptance row was asking for a budget that existed nowhere a reader could find it. Headline: at the 256 B size that dominates real traffic, GCM costs **3 µs** more than CTR; the ML-DSA sign a client pays per authentication is **2.7 ms**. **The ceiling is still NOT pinned:** `acceptance.md` requires one reference *low-end* device and the recorded run is a 16-core arm64 Mac, which is the opposite. Nothing here is a regression gate — one desktop run is a baseline, not a threshold | **B-1** |
| ~~`at_chops` `pqOpen` lets an `ArgumentError` escape~~ — **fixed in at_chops 3.4.2** (unpublished): a wrong-length secret key or KEM ciphertext now arrives as `PqOpenException(malformedEnvelope)`. `NskeyProvider`'s client-side guard stays until at_client's floor rises past 3.4.1 | `at_chops` |
| ~~The CK cache and the owner's own nskey privates are process memory only~~ — **half of this was wrong.** Content keys are a genuine cache: the read path re-fetches the `__ck` conveyance record and re-opens it, so a restart costs a round trip, not data. The nskey private is the real exposure, and [decisions.md 21](decisions.md#21-ss-3-where-key-material-lives-and-what-the-substrate-stops-storing-2026-08-03) ruling 1 files it into `AtKeys` on arrival. **Owed:** implement that filing, plus the current-`ckKid` pointer (ruling 2) so a restart stops minting a fresh CK per destination | **SS-3** / **SS-4** |
| ~~`B-1e` does not work~~ — **found and fixed 2026-08-04** ([decisions.md 26](decisions.md#26-uc-a44-a-conveyance-that-loses-the-race-to-its-own-announcement-2026-08-04)). The two-client harness exposed it on its first run: the content-key conveyance was written local-first, so it reached the recipient's atServer only via sync — 31 seconds later in the captured reproduction — while the notification went out immediately over the monitor. The receive path raised `ContentKeyUnavailableException` correctly and the dispatch loop swallowed it at `finer`, dropping the notification silently with no retry. Both notify entry points now route the conveyance remote-first (the same rule as the `__ssenv` ordering fix), and the dispatch `catch` logs at `warning`. **UC-A4.4 is met**, live-covered in `tests/at_end2end_test/test/pq/nskey_notify_test.dart` (split out of `concurrent_notify_test.dart` 2026-08-08). **UC-A3.4 is NOT** — corrected 2026-08-09: both live notify tests are alice→bob, so the SELF direction (alice1→alice2) is asserted against a mock only. The harness limitation that made it unwritable is gone — `ConcurrentClients` and `EnrolledClient` both exist — so it is owed rather than blocked (#2093). Still open, recorded in 26.3: a notification whose transform throws is gone, with nothing re-delivering it when the missing piece lands |
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
barrel**; `AtClientPreference.keyEstablishmentAlgo` is read by `KeyPackageRegistration` and
`enrollmentKeyPackageBuilder`; `sendEnvelope` seals under the **recipient's** `alg` at the strongest
suite both sides list; `NskeyAdvertisement`/`ResolvedNskey` carry `alg` **and** `suites` and
`PublishedNskeyKeyRing` mints under the preference; `at/nskey/MLKEM1024/AES/GCM` is the second
conveyance provider id, registered on every client whatever this atSign mints. `at_auth` gains
`KeyAlgorithmType.mlKem1024` (additive — that enum's documented contract is never to reject an unknown
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
Parity for every other atServer implementation is a tracked follow-up so it cannot silently diverge.
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
([14.18](#1418-the-remaining-d1-initial-development-sequence) step 16) — so what is still owed is
the part that gives it something to send: **minting** a new KEM key, **marking the old one retired**
and **republishing the package**. Nothing rotates yet, and nothing calls `update` in production.
✅ **[#2133](https://github.com/atsign-foundation/at_client_sdk/issues/2133) was retitled to
`enroll:update` and given a status block on 2026-08-18**, which is also when `blockers.dart`'s `ke2`
constant stopped saying "neither half is built" — it had said so since the client half landed, and it
is the string anyone greps to find out what KE-2 owes.
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

### ON-1 — PQ-native greenfield onboarding + legacy-interop opt-out · at_client, at_client_flutter · M — **ACCEPTANCE COMPLETE 2026-08-08** ([decisions 52](decisions.md#52-on-1-a-greenfield-atsign-starts-where-a-retrofit-ends-2026-08-08))  *(critic gap — UC-A1.1; amended by decisions 37)*
**Landed:** `pqNativeOnboard` (at_client) over `AtOnboardingRequest.signingAlgoType`
+ `mintLegacyMaterial` + `metadataBuilder` and a PQ-native mint (at_auth 3.4.0).
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
a CRAM activation with `--signingAlgoType mldsa65` against a real atServer,
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
`AtClientPreference`'s default posture from `ReleasePosture.migration()` to
`ReleasePosture.postQuantum()` — one edit that flips all five rollout axes
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
([decisions 70](decisions.md#70-workstream-a-capstone-releaseposture-the-five-flags-as-one-value-2026-08-10)).
⚠️ **This paragraph used to say local and namespace-less keys route to legacy
and are refused, so "the SDK's own namespace-less internal writes need their own
decision".** Both halves are now settled and neither gates R-2: `local:` records
are written unencrypted and exempt
([decisions 107](decisions.md#107-a-local-record-is-not-encrypted-and-the-legacy-refusal-exempts-it-2026-08-17)),
and the namespace-less case named there — a legacy recipient's `shared_key.*` —
never reaches the refusal at all
([14.33](#1433-closed-the-shared_key-refusal-was-never-reachable)). The one
genuine instance is a key-construction bug in `NotificationService.send()`
([14.35](../implementation-plan.md#1435-notificationservicesend-throws-away-the-namespace-it-was-given)).

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
**Acceptance → [acceptance.md](../acceptance.md):** the five rollout axes under the flipped default
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

**Package versions & release sequencing** (single reference — publish in dependency order; two majors —
`at_auth` 4.0 (S-5, WASM split) and `at_client` 4.0 (R-2, the flag flip) — at different times):

| #  | Package             | Bump                          | Project(s) | Why |
|----|---------------------|-------------------------------|------------|-----|
| 1  | `at_chops`          | minor `3.2.1 → 3.3.0` **(published 2026-06-23, done)** | P-1    | stateless functional core + HPKE `pqSeal`/`pqOpen`; `@Deprecated AtChopsImpl` shim |
| 2  | `at_chops`          | minor `3.3.0 → 3.4.0` **(published 2026-07-17, done)** | P-2 | #2030 (`at_chops_ffi` barrel + `AtPqc` + `AtSignatureAlgorithm`) landed the 3.4.0 bump on trunk 2026-07-03 (+ #2046); P-2's `mldsa65` verify branch (#2056, 07-06) and #2039 (AES-GCM FFI, 07-09) folded into the same slot, which then published. Minor under the one-time semver exemption ([decisions.md](decisions.md) 2026-07-03) |
| 2b | `at_chops`          | minor `3.4.1 → 3.5.0` **(published 2026-08-11, done)** | — (trunk) | `RsaSignatureAlgo`; PQ key/ciphertext/signature length validation across both backends; `MlDsa65FfiAlgo.verifyBytes` throws `StateError` on an incapable libcrypto. **Not a PQ-program release** — it took the version number the spike had been claiming, which is why row 3 moved up |
| 3  | `at_chops`          | minor `3.5.0 → 3.6.0` **(in-tree, UNPUBLISHED)** | KE-1 | `AtKemAlgorithm.newSeed` + `keyPairFromSeed`; `MlKem1024PureDartAlgo`; `pqSeal ver 0x03` (RFC 9180 at KEM `0x0042` / HKDF-SHA384 / AES-256-GCM); RFC 9180 Base mode as `ver 0x02`; `HkdfSha384`; `ChaCha20Poly1305Algo`. ⚠️ **MINOR because the two seed methods are abstract members on the exported `AtKemAlgorithm`** — an external `implements` must add them. at_client pins `^3.6.0`, and workspace resolution hides the gap |
| 4  | `at_commons`        | minor `5.11.0 → 5.12.0` **(published 2026-07-04, done)** | SS-1a | `EnrollParams.metadata` + `signingAlgo`; flattened `listns`; pkam `mldsa65` literal. *(at_commons has since published 5.13.0, 2026-07-17, outside this program.)* |
| 5  | `at_auth`           | minor `3.2.0 → 3.3.0` **(published stable 2026-07-17, done)** | S-1 | additive: extend `AtKeys` in place (deprecate legacy); `AtKeysIo` runtime persistence; `InMemoryAtKeysIo`. The rc1 → stable promotion is **closed** (re-verified against pub.dev 2026-08-08), so S-6 and SS-2's at_auth work have the stable version they pin against |
| 5b | `at_auth`           | minor `3.3.0 → 3.4.0` **(in-tree, UNPUBLISHED)** | KE-1, ON-1 | opened 2026-08-03 (`936241d8f`): `KeyAlgorithmType.mlKem1024`; the `.atKeys` passphrase envelope derives from a random per-file salt (was salted with the passphrase itself). **This is the open at_auth slot** — ON-1's `mintLegacyMaterial` folds in here rather than opening a new version |
| 6  | `at_auth`           | **major `3.4.x → 4.0.0`**     | S-5        | breaking WASM cut: `FileAtKeysIo` → `at_auth_io.dart`; default removed; registrar → `package:http` |
| 7  | `at_client`         | minor `3.14.x → 3.15.x`       | S-2…B-2, KE-1 | `at_auth ^4.0.0`; `CryptoContext.keys`; nskey data path; rotation; the selectable KEM. **= D1 GA**. ⚠️ **3.13.0 and 3.14.0 both published 2026-07-17** so the GA slot has moved off 3.14.x; trunk is already 3.14.1. For compatibility purposes the baseline is **3.13.0** ([`decisions.md` §91.4](decisions.md#914-what-is-released-and-therefore-what-must-still-be-read)) — re-derive the target minor at execution against pub.dev. ⚠️ **S-2's `CryptoContext.keys` (#2076) is on trunk but unreleased** — it merged after 3.14.0 published, so the next at_client release is the first that carries it. ⚠️ **gated on row 3** — this release cannot go out against an unpublished `at_chops 3.6.0`, and a published 3.5.0 does not discharge that gate |
| 8  | `at_client`         | **major `3.15.x → 4.0.0`**    | R-2        | default posture → `ReleasePosture.postQuantum()` (all five axes, [decisions 70](decisions.md#70-workstream-a-capstone-releaseposture-the-five-flags-as-one-value-2026-08-10)); plus the normal major-version deprecation cleanup (orthogonal to the rollout, [decisions 56.4](decisions.md#564-from-the-pq-projects-view-40-is-final-3x-with-different-flag-defaults)). *(selfEncryptionKey stop-existing moved to a later ecosystem-gated release, [decisions 37](decisions.md#37-legacy-key-material-is-retained-until-the-ecosystem-is-pq-not-the-atsign-2026-08-05))* |
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

**Status: RESOLVED in design, PARTLY BUILT 2026-08-11. The door opens.** `enroll:update` ([`decisions.md` 91](decisions.md#91-signature-agility-the-apkam-auth-key-stops-being-the-enrollments-signing-key-2026-08-11)
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
| `at_client` | 340 |
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
> ruling 1 makes `now|rollout1|rollout2` a new axis on `ReleasePosture`, and
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

`AtClientImpl._resolveFullPrivilege()` returns **true unconditionally when
`enrollmentId == null`**, and `ApkamSigning.enrollmentId` substitutes the
sentinel `'primary'` when there is none. So a legacy PKAM client that happens to
hold an `AtKeysIo` publishes `public:_apsk.primary.a.__e@<atSign>` and signs
approval-chain links as `"primary"`.

Found while surveying for [14.13](#1413-a-passive-by-default-flag-surveyed-not-built),
and worth separating from it: a flag would *hide* this rather than resolve it.
The question is whether an owner-keys client should be in the enrollment trust
chain at all, and if so under what identity — `'primary'` is a name no
enrollment record carries.

### 14.15 Pre-PR rails checklist

No PR opens against this branch until the published atServer image verifies
ML-DSA PKAM (owner's call, 2026-08-08). One thing must still be true by then:

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

Updating the #1889 tree to the current state meant auditing every open issue's
own deliverables against the code rather than against the plan. Four things were
owed that no ledger recorded — and two plan claims were wrong, now corrected in
place (the layer-3 AAD literal, and UC-A3.4 below).

1. **The performance ceiling is not pinned.** [acceptance.md](../acceptance.md)
   asks for the deltas measured on *one reference low-end device*, with the
   ceiling pinned when the harness lands. The harness exists and has been run —
   but only on a 16-core arm64 Mac, which is the opposite of the device the
   criterion names. Until it is re-run, "performance is measured, not assumed"
   is not yet true. B-1's own unmet acceptance requirement (#2010).
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
   outruns its key, which is still dropped
   ([decisions 106](decisions.md#106-a-notification-that-outruns-its-key-is-dropped-not-parked-2026-08-16),
   [14.30](../implementation-plan.md#1430-a-content-notification-can-outrun-the-key-that-opens-it))
   (#2093).
3. **SS-4: an interrupted mint does not resume.** The acceptance bullet asks
   that it resume rather than re-generate; there is no persisted in-progress
   marker, so it starts over. Worth deciding whether that is still required —
   the mint lock and the immutable create may already make re-generation safe,
   and the acceptance text predates both (#2087).
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


### 14.17 Signature agility — what is built, and what is owed

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
     `inUseSigningAlgorithms`, defaulted from `ReleasePosture`. The deprecated
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
4. **The rollout axis.** One `ReleasePosture` flag switching all three writer
   behaviours together (mint signing keys, publish the array, emit
   multi-signature envelopes). **The axis has no name yet** — see
   [`design.md` 9.7](../design.md#9-subsystem-g--signature-agility-the-authsigning-key-split).
5. **The rollout harness.** Two stage-parameterised executables plus the 3×3
   matrix in [`acceptance.md` 16.5](../acceptance.md#16-g1--signature-agility-and-the-rollout-matrix),
   with the failing cell asserted by its specific error.
6. **`enroll:update` parity for every other atServer implementation** — needs
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

### 14.18 The remaining D1 initial-development sequence

Ruled 2026-08-11 by a walk through every open item
([`decisions.md` 93](decisions.md#93-the-d1-remaining-work-sequence-and-the-rollout-axis-becomes-real-2026-08-11)).
This is the **order**, not the inventory — each row points at the entry that
holds the detail. **D1 initial development ends at step 34**, when the stacked
PRs are merged; publishing and R-2 follow it.

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
| 3 | **DONE 2026-08-12 — one envelope shape, RFC 7515 general serialization**, `{payload, signatures:[{protected, signature}]}` with `{alg, kid, v}` in each `protected`. Deleted `signedEnvelopeVersion`, `jwsEnvelopeVersion`'s flattened form, `envelopeVersionOf`'s dispatch, the `wrapperFields` ternary in `ApkamSignedAdvertisedKeys.verify`, and `envelopeVersion` as a `ReleasePosture` axis. Also took `hashingAlgo` off `signEnvelope` — `alg` names the hash, so nothing unsigned selects a routine — and retired UC-C1.3, the rollout's envelope axis, which had nothing left to drive. The `.mjs` adjudicator moved `flattenedVerify` → `generalVerify`; vectors regenerated at `test/vectors/jws_envelope.json`. **Found en route:** `publishPendingLink`'s already-published check compared a top-level `['signature']` the envelope does not have, so `null == null` matched every time and a different link conveyed later was silently never published | [`decisions.md` 95](decisions.md#95-the-envelope-keeps-one-shape-and-a-retained-key-says-so-2026-08-12) ruling 1, **superseding [91](decisions.md#91-signature-agility-the-apkam-auth-key-stops-being-the-enrollments-signing-key-2026-08-11) ruling 12**'s bespoke container |
| 4 | **DONE 2026-08-13 — ruling 2 landed, so all of step 4 is complete and step 6 is unblocked.** Ruling 2 in three commits: `6462ae786` (the advertisement becomes `{v, createdAt, keys:[{use, alg, pub, kid}], suites}` with one `toPayload`/`fromPayload` codec replacing a map literal in `_mint` and a hand parser in `verify` 250 lines apart), `d28ef48a9` (a key that is not its algorithm's length is refused — a kid is the digest of whatever bytes are carried, so it matched a forged key as readily as a real one), `69449603e` (the reader skips entries it has no KEM for and picks the strongest it can use, which has to ship before any writer emits a second key). **Three things the ruling got wrong**, all corrected in `decisions.md` 94: `_apsk` entries never carried `status`; `status` and `KeyEntryStatus` are deferred **entirely to step 5** so no dead field ships (gkc, 2026-08-13); and at_auth cannot reach `PackageKey` because at_client depends on at_auth, so one vocabulary means one **wire spelling** across two Dart types. `createdAt` was added for symmetry with `KeyPackage`; `v` stays 1. Rails: at_client 1188/1188, functional 146/146. One key-entry vocabulary across all three advertising records — `{use, alg, pub, kid, status?}` inside `{v, keys:[…], suites}`. **Landed 2026-08-12:** ruling 3 (one kid function, at_auth's `publicKeyKid`, over the key's raw BYTES — `apskKid` hashed the base64 text and `nskeyKidOf` the material, and every kpid changes value); ruling 4 (`v`, `alg`, `suites` required, both `legacy*Suites` deleted); ruling 5 (one `SecretSharingAlgos.bestSuiteBetween`); **ruling 6** — `pq_envelope.dart`'s `pqSealToBase64`/`pqOpenFromBase64`, both taking `info` and `version` as **required** arguments and constructing neither, so there is nothing inside the shared code for the two substrates to converge onto. at_chops' `pqSeal`/`pqOpen` now require `info` too, which makes a shared binding a **compile error** rather than a convention — it was reachable before, because `info` was optional and `info ?? Uint8List(0)` made omission and empty the same binding. **Found en route:** the pairwise substrate had NO test that could fail on a converged binding — dropping the label from all three pairwise/enrollment call sites left the suite green at 1180/1180 — so the production-fed differential in `pairwise_secret_sharing_test.dart` was built first and proven by that same symmetric mutation, which now turns exactly one test red. **Still owed: ruling 2** — the nskey advertisement gains a `keys` list and adopts the shared spelling | [`decisions.md` 94](decisions.md#94-three-records-advertise-keys-and-only-one-of-them-speaks-the-vocabulary-2026-08-11) — ⚠️ **before step 6**, or that parser becomes the third hand-rolled codec for one shape |
| 5 | **DONE 2026-08-13 — the `retired` key path, in three commits.** `6a5eac838`: `PackageKey` gains `status`, a `KeyEntryStatus` of `active` or `retired`, and `bestKeyFor` on both a key package and an nskey advertisement passes a retired key over, so `kpid` is the *active* enc key's kid. Emitted only when retired — absent already reads as active — and an unrecognised value reads as retired, the one reading that cannot make a build use a key its owner withdrew. `f956b2146`: `PersistedApkamKeys` becomes `{encKeys: [PersistedEncKey]}` and `KeyPackageRegistration` expands, advertises and answers for every held key, with `encKeyFor(kid)` replacing `encSecretKey` and `heldKpids` listing every address. `f6fc3796e`: the sweep, the wake-up subscription and the sync listener cover every held address (`EnvelopeAddressing.regexForAny`/`sweepRegexForAny`), and `_consume` opens with the key the envelope names. **Three things ruling 9 got wrong or omitted**, all recorded in `decisions.md` 95: the sweep filter is a **fifth** consequence and the one that makes the other four reachable; the keyfile already records the status (`AtKeysMaterial.KeyPartStatus`, `AtKeys.retireKey`, and an `AtKeysAssurance` rule enforcing one active `publicEncapsulation` per enrollment and algorithm), so deriving it from `createdAt` was wrong; and `dead` material is not adopted at all. Rails: at_client 1210/1210, functional 146/146. **Nothing rotates yet** — the writer is step 16. ⚠️ app-facing: `PersistedApkamKeys` is what apps build in `loadApkamKeys`/`saveApkamKeys` | [`decisions.md` 95](decisions.md#95-the-envelope-keeps-one-shape-and-a-retained-key-says-so-2026-08-12) rulings 6–9 — without the plural holding the field is decorative. The **name collision** was settled 2026-08-12 (gkc) and landed as ruled: the per-entry wire value is a Dart `KeyEntryStatus`, and `KeyPackageStatus` — the reader's verdict on a whole package (`present`/`absent`/`rejected`/`unsupported`) — keeps its name. Nothing renamed |
| 6 | **DONE — mostly with step 2a, completed 2026-08-13.** `parseApskValue` reads the array **and** the released bare string, refuses a structured value advertising nothing it understands rather than guessing, and skips entries whose `use` or `alg` it does not know; `apsk_formats_test.dart` covers all of that plus "the array form is unmistakable to a bare-RSA consumer". Finished on 2026-08-13 by giving `ApskSigningKey` a `status` and having `apskSigningKeys` read it — **keeping** a retired entry, because this list is what verifies stored envelopes and a retired key is precisely what signed the older ones. `KeyEntryStatus` moved from at_client to **at_auth** in the same change so all three advertising records name one type, narrowing [94](decisions.md#94-three-records-advertise-keys-and-only-one-of-them-speaks-the-vocabulary-2026-08-11)'s "one vocabulary cannot mean one Dart type" — that was true of a type living in at_client, and at_auth is the lower package. **Found by the re-verify:** `design.md` 9.3's JSON example omitted `kid`, which the reader requires, so the document the design showed is one every reader treats as empty and then refuses; corrected, and pinned. `advertised.first` and the singular `ParsedApsk` are steps 7–9's business, not a gap here | [`design.md` 9.3](../design.md#9-subsystem-g--signature-agility-the-authsigning-key-split) |
| 7 | **DONE 2026-08-13.** `SigningAlgoType.strongestFirst` + `strongestOf` in at_chops — purely additive (two statics on the existing enum; no member added, moved or renamed, so it does not touch the unresolved 3.6.0-versus-major question). Deliberately **not** declaration order: members are declared in the order they were added and reordering them is a wire change, so preference is a second statement. `mldsa65` first, categorically — the only member Shor does not break — then RSA-4096, `ed25519`, `ecc_secp256r1`, RSA-2048 by classical security level. Total on purpose: a partial order leaves the choice undefined for exactly the pair nobody thought about. **The tripwire is completeness, not just the literals**: a new `SigningAlgoType` left out of the order turns `test/signing_strength_test.dart` red, which is what stops it becoming silently unrankable. Wired straight into `parseApskValue`, which took `advertised.first` — the order entries arrive in is the *signer's* choice, so an enrollment advertising ML-DSA-65 beside RSA-2048 was verified against whichever it listed first | [14.17](#1417-signature-agility--what-is-built-and-what-is-owed) |
| 8 | **DONE 2026-08-13.** `requireAlg` is gone rather than rewritten: the algorithm is now *resolved* — from what the envelope's `signatures` and the signer's `_apsk` have in common, taking the strongest by `SigningAlgoType.strongestFirst` — and then its key is fetched, where before one advertised key was taken and the envelope was required to match it. Its refusal survives in a different form: no algorithm in common is refused naming both lists. `ParsedApsk` went plural (`keys`, `keyFor(algo)`; `signingAlgo`/`publicKey` survive as strongest-of getters), and the bare RSA form parses to a one-entry list so both published forms are one shape to the caller. The two JOSE `alg` switches — one on the sign side, one on the verify side — became one `_joseAlgFor`, since two would be two chances to disagree | ⚠️ an inversion, not an addition |
| 9 | **DONE 2026-08-13, with step 8** — the two do not separate: resolving the strongest shared algorithm *is* walking the entries. `verifyEnvelope` selects its entry by algorithm rather than taking `signatures.first`, verifies only that one, and refuses on failure with no fallback. **Found en route and fixed:** `signerEnrollmentId` reads `signatures.first.kid` while the verified entry is now chosen by algorithm, so the two could be different entries — append a signature under a stronger algorithm carrying another kid and a caller acts on a signer whose signature was never checked. `SignedEnvelope.fromJson` now refuses an envelope whose entries name more than one signer, which is a structural claim about this shape rather than a verify-time check. UC-G1.7 is covered for the first time, four rows | [`design.md` 9.4](../design.md#9-subsystem-g--signature-agility-the-authsigning-key-split) |

**A reader understanding no entry refuses outright** — no downgrade, no fallback
to a derivable legacy key ([`decisions.md` 93](decisions.md#93-the-d1-remaining-work-sequence-and-the-rollout-axis-becomes-real-2026-08-11) ruling 2).

**Stage 2 — the unblocker. The writer half cannot start before this.**

| # | Work |
|---|------|
| 10 | **DONE 2026-08-13 — one resolver, not a materialised projection.** `AtKeys.authenticationFor(enrollmentId)` returns the AtChops and the PKAM algorithm, with typed material winning wherever the keyfile holds it for that enrollment and the flat fields answering only where it holds none; `authenticationAlgorithmFor` is the algorithm half, so a caller holding an injected AtChops does not build one `toAtChops` would throw on. `AtAuthImpl.authenticate` and `AtClientImpl._createAtChops` both move onto it. **Ruling 7 as written could not be built** and is amended in place ([`decisions.md` 91.3](decisions.md#913-the-rulings)): filing a projected material makes `toJson` emit `version`/`atsign`/`keys` — the guard is `keys.isEmpty` and both stores stamp `atsign` first — which breaks the byte-identical legacy round-trip [91.4](decisions.md#914-what-is-released-and-therefore-what-must-still-be-read) promises, and on a retrofitted keyfile the one-active-`privateAuthentication`-per-document rule refuses the add outright. Four shipping shapes hold nothing to project from: a pre-typed `.atKeys`, an `rsa2048` first onboard, an OTP enrollment, and an onboard handed its keys by the caller. **Found en route and fixed:** `_createAtChops` picked its keypair off the algorithm `_resolveSigningAlgoFromKeyMaterial` had recorded, and that records nothing when its own read throws — so a transient keyfile failure made a retrofitted client PKAM with the *flat* enrollment's key while its typed material sat in the same file. Its comment claimed it mirrored `AtAuthImpl`; it did not. Rails: at_auth 257/257, at_client 1218/1218 |
| 11 | **PARTLY DONE 2026-08-13 — the wiring half.** ⚠️ **The nullability was never the problem, and the blocking claim was measured rather than inherited.** `apkam_signing.dart`'s dartdoc says sourcing from `AtKeys` "cannot land until every client has an `AtKeysIo` — today it is nullable and most apps supply none". Measured over the 22 repos on disk that depend on at_client: **0 of 22** supply one to a client and **0 of 22** use `fromAuthSession`, so the claim is TRUE — but the dominant cause is one SDK line, not app behaviour. `AtOnboardingServiceImpl.authenticate()` built a `FileAtKeysIo` for `AtAuth` and then created the client without it, so every `at_cli_commons` consumer (at_talk, sshnoports, noports-tools, at_demos, ogentic) inherited a source-less client. **Fixed:** `_initAtClient` takes the source and threads it to `setCurrentAtSign`. The injected AtChops still authenticates — this only gives the client the source for what AtChops cannot answer. ⚠️ **Deliberately NOT done: an `atKeysIo ??=` default on at_client_flutter's `AuthService.authenticate()`.** `AtAuthRequest`'s constructor already refuses a request with neither `atKeysIo` nor `atAuthKeys`, so the default could only ever fire when the caller supplied `atAuthKeys` — an app that loaded its own key material — and pointing it at a keychain that may hold another atSign's keys, or none, is a guess. The asymmetry with `onboard()`'s `??=` is correct: onboarding mints keys and needs somewhere to write them. ⚠️ **The null case is a tested, deliberate property**, not an oversight — `no_atkeysio_inertness_test.dart` pins that a source-less client performs zero PQ writes at startup, which is what protects the long-lived cicd atServers, and the e2e pack builds its clients through `setCurrentAtSign` directly so this change does not reach them. ✅ **DONE 2026-08-13, with step 12:** the signing half — `signingKeys` sources from `AtKeys` rather than reading the APKAM auth keypair out of `atChops`. Built once, as step 12's per-algorithm accessor |
| 12 | ✅ **DONE 2026-08-13.** `AtKeys.signingKeysFor(enrollmentId)` (at_auth) returns every active signing keypair the enrollment holds, one per algorithm, strongest first; `ApkamSigning.signingKeys` (at_client) is a `Future<List<ApkamSigningKeys>>` reading it through `AtClient.atKeysIo`. `ApkamSigningKeys` now carries its `algorithm` and `signEnvelope` takes it from there rather than a separate `signingAlgo` argument — a key and an algorithm arriving separately can disagree, and the resulting signature verifies against nothing. ⚠️ **Selection is by the keyId shape `sign:<enrollmentId>:<algo>:<n>`, NOT by the `privateSigning` role**: `PqSigningRoot` files the atSign-wide signing root under that same role with no enrollment id, so a role filter hands an enrollment a key that was never its own — the same defect shape as 14.19 item 6. Proven by mutation: selecting on the role turns two tests red. **The empty case answers with the APKAM authentication keypair**, which is what ruling 10 keeps in the `_apsk` array permanently, so the accessor is live from this commit rather than waiting on a writer, and `now`-posture envelopes stay byte-identical (the stored JWS vector re-signs to the same bytes). That also covers the source-less client, which is a deliberate tested property. Read per call, not cached: a cached copy goes stale the moment a rotation retires what it held. **The minting/filing half is NOT here** — `fileSigningMaterial` still has no production writer, and which algorithms to mint is the in-use set's decision, so it stays step 18. Rails: at_client **1228/1228** (2 skipped), at_auth **266/266** |

**Stage 3 — the `_apsk` writer half (rollout 2).**

| # | Work |
|---|------|
| 13 | ✅ **DONE 2026-08-13.** `apskAdvertisement` composes from a **list** of keys rather than one `(apkamPublicKey, signingAlgo)` pair, so a second algorithm's key can be advertised beside the first; `ApskSigningKey.forPublicKey` builds an entry and derives its `kid`, which is never a caller's to supply. `status` is emitted **only when retired**, so an advertisement that has never rotated is byte-identical to what the single-key composer wrote. The enrollment-request site still sends one key — at request time the enrollment holds nothing but its freshly minted APKAM keypair, and a second arrives by `enroll:update` (step 16) once step 18 mints one. **`publishPublicSigningKey`'s fate, settled:** it stays the only writer for an `_apsk` no `enroll:request` can carry (a client with no enrollment publishes under `primary`, which has no enrollment record). It now publishes `publicSigningKeyValue` — the **bare** key when the client holds exactly one `rsa2048` key, the array otherwise — which is the same rule `_apskFor` uses for `apsk`-versus-`apskLegacy`; the two must agree because they describe one record. It also **republishes on a change**, closing [decisions.md 91.1](decisions.md#911-what-is-wrong-today) cost 2: it used to read the record, log "have already published" and return, so a rotated key never reached the atServer and every envelope signed with the new one was verified against the old. Proven by mutation: restoring the absent-only condition turns exactly the republish test red. Rails: at_client **1234/1234** (2 skipped), at_auth **269/269** |
| 14 | *(done in step 2a)* `EnrollParams.apsk`/`apskLegacy` are populated at all three submit sites. ⚠️ **This read "Only the atServer half of `apskLegacy` remains" until the 2026-08-14 wrap-up, and that half had merged two days earlier** — at_server `6a86fbcc`, an ancestor of `origin/trunk`, re-verified with `git -C ~/dev/atsign/repos/at_server branch -r --contains 6a86fbcc`. Step 2a was corrected on 2026-08-13 and this row was not, which is how a reader working top-down would have rebuilt merged work |
| 15 | ✅ **DONE 2026-08-13.** `signEnvelope` takes a **list** of keys and emits one signature entry per key, in the order given — which is what the RFC 7515 general serialization the envelope already used is for. `wrapAndSign` passes every key `signingKeys` returns rather than its strongest: the **verifier** chooses, taking the strongest algorithm the envelope and the published `_apsk` share, so signing only under this build's strongest would be unverifiable to any peer that has not implemented it — an envelope carrying both is readable by the upgraded peer and the un-upgraded one, which is the rollout problem in one sentence. The payload is encoded **once** and every entry signs its own protected header joined to that same text, so the entries are alternatives rather than a chain. `SignedEnvelope.fromJson` already refused an empty signatures array and a multi-**signer** document, so the writer builds through it and inherits both refusals. ⚠️ **UC-G1.7's two-signature fixture was hand-assembled** from two single-signature envelopes, so that whole group was a test of the fixture and would have passed against a writer that could not emit two signatures at all; it now drives the real writer. Proven by mutation: signing with `[keys.first]` turns the multi-signature test red. Nothing files per-algorithm signing material yet, so every envelope still carries exactly one signature today, and the stored JWS vector re-signs byte-identically. Rails: at_client **1237/1237** (2 skipped), at_auth **269/269** |
| 16 | ✅ **DONE 2026-08-13, in five commits `e04040ac1`…`d467ed3b5`** — two code, three docs (this row said "in two commits", written before the doc sweep and the wrap-up corrections landed). `AtEnrollment.update` takes an `EnrollmentUpdateRequest` and an `EnrollmentUpdater` sends it, beside `EnrollmentApprover` and deliberately not on it: the approver's verbs need a connection holding `__manage` and act on somebody else's enrollment, while this one needs no privilege and can only act on the enrollment the connection *is* — the atServer refuses an owner connection here rather than waving it through. The request refuses at construction to be built naming nothing to change, with a public key and no private half, with a key and no algorithm or an algorithm and no key, with both `_apsk` shapes, or with an advertisement of no keys. **Found en route: the wire vocabulary was one field short, so this row's "only the caller is owed" was wrong.** `EnrollParams.apkamPublicKeySignature` existed with its own round-trip test, but `EnrollVerbBuilder.buildCommand` never copied it into the params it builds — and a `toJson`/`fromJson` round trip is equally true of a field nothing can send, so the test could not see it. **Two rulings this took:** `signingAlgo` is **always** sent, so the effective algorithm the atServer interpolates is the one signed here and the literal `"null"` can never come from this emitter (pinned regardless — a second implementation has to know the server accepts it); and the public API takes two key-material **strings**, not an `AtPkamKeyPair`, because at_chops deprecates that type and a new signature carrying it hands every caller a deprecation. `ecc_secp256r1` is refused rather than signed: at_chops' pkam-mode signer selects an RSA implementation for everything that is not `mldsa65`, so an ECC key would be signed as though it were RSA — and an ECC APKAM key lives in a secure element whose private half is not a string anyone can pass. **Proven by two mutations**, against tests that re-run the atServer's own `ApkamSignatureVerifier` branches rather than asserting through the signer: signing everything as `rsa2048` turns exactly the mldsa65 arm red (that arm is the only one that can see an algorithm mix-up), and dropping the algorithm from the signable turns all three signature tests red (both arms verify real bytes). ⚠️ **Nothing persists a rotated keypair** — [14.19 item 11](#1419-small-items-raised-2026-08-12-and-not-yet-acted-on). Rails: at_commons **517/517**, at_auth **288/288**, at_client **1237/1237** (2 skipped), at_onboarding_cli **39/39**. **THE PoP CONTRACT, read from at_server `6a86fbcc` `enroll_verb_handler.dart` `_verifyApkamPublicKeyPossession` and `apkam_signature_verifier.dart` — do not re-derive it:** signable is `utf8.encode('<enrollmentId>|<apkamPublicKey>|<signingAlgo>')`, signature travels **base64**, signed by the **NEW** private key. Three things a guess gets wrong: (a) `signingAlgo` is the **effective** one, `request.signingAlgo ?? record.signingAlgo`, string-interpolated — so a null becomes the literal `"null"` in the signed bytes, and a client that omits it must know the record's current value; (b) **mldsa65 signs the message DIRECTLY with no hash** (`MlDsa65PureDartAlgo.verifyBytes`), while rsa2048/ecc go through `AtChopsImpl.verify` with `HashingAlgoType.sha256` — a client that hashes for both fails only on the PQ path; (c) `AtSigningMode.pkam`, never `data`, which signs with the *encryption* keypair. The server also refuses `signingAlgo` without `apkamPublicKey`, and `enroll:update` is **self-only** and **approved-only**. ⚠️ **Adding a member to `AtEnrollment` touched 7 `Mock implements` in three packages** (at_auth 2, at_client 4, at_onboarding_cli 1), plus `AtEnrollmentImpl`, which is the **production** class and got a real implementation rather than a stub — not an eighth mock, as an earlier draft of this row said. All three suites re-run; the mocks are safe because no production path calls the new member, and they would have broken at RUNTIME, not analyze |
| 17 | ✅ **DONE 2026-08-13.** `AtClientPreference.inUseSigningAlgorithms` — a `Set<SigningAlgoType>`, final at construction and stored unmodifiable, defaulted from a new fifth `ReleasePosture` axis and overridable per preference. **The four things ruling 16 left open were ruled by gkc and are recorded in [`decisions.md` 91.3](decisions.md#913-the-rulings) ruling 16 with their reasoning:** defaults `{}` in 3.x and `{mldsa65}` in 4.0; a `Set`; final at construction; and an algorithm this build cannot sign an envelope under is refused at construction with an `ArgumentError` rather than skipped. ⚠️ **The doc sweep this owed was bigger than the row** — three documents enumerated the posture's axes and all three still listed the **signed-envelope version**, deleted at step 3: [`decisions.md` 56.4](decisions.md#564-from-the-pq-projects-view-40-is-final-3x-with-different-flag-defaults)'s table, its capstone entry [`decisions.md` 70](decisions.md#70-workstream-a-capstone-releaseposture-the-five-flags-as-one-value-2026-08-10), and `roadmap.md`'s axis list. The count stayed five across the swap, which is precisely how a stale enumeration survives review. Acceptance gained UC-C1.7 and UC-C1.6's "UC-C1.1–C1.5 prove the arms" was corrected — C1.3 is withdrawn. `design.md` 9.6's strength order still showed the three-member ruling rather than the five-member total order step 7 shipped. **Nothing reads the set yet — step 18 is its only consumer**, so this commit is a preference and its refusal, not a behaviour change. **Proven by four mutations**: each posture default flipped reddens its literal pin, disabling the signable check reddens the refusal test, and returning the caller's own set rather than an unmodifiable copy reddens the containment test. ⚠️ **The 1240/1240 in this commit's message was measured before the doc edits and does not hold for the commit as landed** — adding UC-C1.7 to `acceptance.md` without a scenario in `test/acceptance/` turns `catalogue_test.dart` red, which is that guard doing its job. Fixed in step 18's first commit, which adds the scenario and the README row count. Rails for 17+18a together: at_client **1245/1245** (2 skipped), acceptance **57** (2 skipped) |
| 18 | **PART 1 DONE 2026-08-13 — the reader and the advertisement; the minter is part 2.** Splitting it was forced by a defect the minter would have shipped: `ParsedApsk.keyFor` took **one key per algorithm** (`where(alg).firstOrNull`) and `verifyEnvelope` checked that one, so ruling 10's retained authentication key works only where its algorithm differs from the minted key's. A post-quantum-native enrollment's auth key is ML-DSA and so is what it mints, which puts two `mldsa65` entries in `_apsk`, and every envelope signed before the split stops verifying — the ordinary 4.0 case. `keysFor(algo)` is now plural and the verifier tries each, refusing only when none verifies; ruling 10 is amended in place with why. **The reader ships before the writer**, which is also why this is two commits rather than one. Also here: `apskEntries`/`apskValueOf` (`apsk_composition.dart`) are the one composition of the `_apsk` record for both its publishers, and they append the authentication key as `retired` once the enrollment holds signing keys — deduped, because one key described as both current and withdrawn is a document a verifier has nothing to choose on. An enrollment holding no signing material advertises exactly what it did before. ⚠️ **The retention half was reversed 2026-08-14 by row B2** under [`decisions.md` 98](decisions.md#98-rollout-1-moves-the-authentication-key-not-the-signing-key-2026-08-14) ruling 2: the auth key is advertised only while it *is* the signer and is never retained, and what `apskEntries` carries beside the active signers is the enrollment's **retired signing keys**. The dedup survives, between an active signer and a retired entry naming the same public half. **Proven by mutation**: restoring the single-key selection reddens the retained-key test. Rails: at_client **1245/1245** (2 skipped), acceptance **57** (2 skipped). ~~**Part 2 owes** the minter itself: mint at start, publish, then file.~~ ✅ **PART 2 DONE 2026-08-13** (`90730a130`, "an enrollment mints its own signing keys, advertising before filing"), and this sentence stayed here reading as owed until 2026-08-18. `SigningKeyMinting` (`signing/signing_key_minting.dart`) mints one keypair per algorithm the in-use set names and the enrollment lacks, retires every held one the set no longer names, and is wired as step 3 of `PqClientBootstrap` (`pq_client_bootstrap.dart:203`); `test/signing_key_minting_test.dart` covers it and `tests/at_functional_test/test/apsk_server_side_test.dart:215` drives it live. The order it owed is the order it shipped in. ⚠️ **That order matters** — filing first makes the client sign with a key its advertisement does not name, and every envelope written in that window is permanently unverifiable, while an advertised key that was never filed costs a verifier nothing and disappears at the next publish. The nskey path's rule is the opposite (`NskeyPrivateFiling.store` files before publishing) because an unopenable *encapsulation* key loses data; the asymmetry is real and worth stating where both are read |
| 18b | ✅ **DONE 2026-08-13.** `SigningKeyMinting` (at_client) mints a keypair for every algorithm the in-use set names and the enrollment does not hold, advertises it, and **then** files it through `WrittenAtKeysIo.update` — the store's atomic verb, because a client's start files conveyed key material through the same keyfile and a hand-rolled read → mutate → write would drop whichever addition flushed first. Wired as the **ninth** `PqClientBootstrap` step, `mintInUseSigningKeys`, gated by `PqStartupGates` and placed **before every step that signs** (seeding, both link publications and the sweep all emit signed envelopes), so a key minted on a start is advertised before anything signs with it. Which writer depends on whether there is an enrollment record: `enroll:update` where there is one — the atServer is the only writer of an enrollment's `_apsk` — and a direct publish under `primary` where there is not. Inert with an empty in-use set (the 3.x default) and inert for a client with no key source, which is the tested no-`AtKeysIo` property. `RsaKeyPair.generate()` rather than `AtChopsUtil.generateAtPkamKeyPair()`, which returns a type at_chops deprecates. **Proven by three mutations**: swapping to file-then-publish reddens the ordering test, dropping the retained authentication key reddens the advertisement tests, and minting an already-held algorithm reddens both idempotence tests. ⚠️ **The second of those mutations no longer discriminates** — row B2 removed the retention it was probing. Its replacement is B2's own pair: gutting `retiredSigningKeysFor` reddens the two retained-signing-key tests, and removing the dedup reddens the third. Rails: at_client **1257/1257** (2 skipped), acceptance **57** (2 skipped) |
| — | *(the original row, kept for its spec pointers)* Mint-on-demand when the in-use set names an algorithm the enrollment lacks. **Spec: ruling 16** (mint locally at start, file it, publish it — a *signing* keypair may, because unlike the auth key it needs no server approval) and **[`decisions.md` 91.3](decisions.md#913-the-rulings) ruling 9** (the array is append-mostly: an algorithm leaving the set stops signing, but its key and its published entry are **retained**, because they are what verify the envelopes it already signed). This is the step that gives `signingKeysFor` something to read — `fileSigningMaterial` has no production writer until it lands |
| 19 | ✅ **DONE 2026-08-13.** The axis is **`SigningRollout`** — `now` / `rollout1` / `rollout2` — on `ReleasePosture.signingRollout`, overridable per `AtClientPreference`, with the in-use signing set **derived** from it rather than stored beside it. **The step opened with a finding that nearly closed it:** the three rollout-2 writer behaviours are inseparable *by construction*, not by three flags agreeing — only minting is a decision, while the array form (`apskValueOf` emits the bare string only for a single active `rsa2048` entry) and the multi-signature envelope (`wrapAndSign` signs with every key the keyfile holds) are consequences of the enrollment holding a second key. Folding the axis away like step 23 was put to gkc and **declined**: the axis earns its place by naming the position, and steps 20–22's driver needs those names. So it names a position and supplies one default, and cannot contradict the behaviour — two stored fields would be two controls over one thing. `rollout1` writes exactly what `now` writes (the reader half needs no gate) and carries the *fleet's* position instead; it is reachable only through the preference, since there are two postures and no general constructor, and an unreachable value would be a rollout position nothing could ever be in. **Proven by three mutations**: giving `rollout1` a non-empty set, ignoring an explicit stage, and letting the stage beat an explicit set each redden their own arm. Rails: at_client **1261/1261** (2 skipped), functional **146/146** at `88ab87b4e` |

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
| 29 | The four audit residuals — perf ceiling on a real low-end device, UC-A3.4 live self-direction, SS-4 interrupted-mint resume, IS-1 record-name drift | [14.16](#1416-four-residuals-the-issue-tree-audit-surfaced-2026-08-09) |
| 30 | `deprecated_member_use` findings across the workspace (340 at_client, 183 at_onboarding_cli, 110 at_auth, 28 at_lookup) | [14.11](#1411-deprecated_member_use-findings-across-the-workspace) |
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
→ at_commons **5.16.0** → at_auth 3.4.0 → at_client's GA minor, and finally
**R-2**, the 4.0.0 posture flip. (⚠️ this said at_commons **5.15.0** until
2026-08-13, a version already on pub.dev; the in-tree in-progress heading is
5.16.0. Check pub.dev against every touched pubspec before acting on this
ladder — a same-value version bump merges silently.)

### 14.19 Small items, raised 2026-08-12 and not yet acted on

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
   material's `keyAlgorithmType` against `SigningAlgoType.values` and returns
   null for anything else, and `authenticationFor` reads null as "no typed
   material for this enrollment" — so a keyfile written by a newer client
   authenticates from the flat fields instead, which on a retrofitted file are
   a *different* enrollment's credentials. The two cases are not the same
   question: "this enrollment has no typed material" and "it has some I cannot
   sign with" want different answers, and only the first should reach the flat
   fields. Not reachable today — `KeyAlgorithmType`'s signing tokens and
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
    exposed the blocker underneath — `KeyPartStatus` was an `enum` whose parse
    threw, and **at_auth 3.3.0 on pub.dev ships the same three values**, so any
    new status made a keyfile unreadable to every released build *in its
    entirety*. gkc chose reader-first over accepting that break, and the
    tolerant reader is now in: status is an open `String` that round-trips
    unmodified, with the forward order stated as `KeyPartStatus.rankOf`.

    **What is still owed, in order:** an at_auth release carrying that reader;
    then the `pending` value; then the rotation arm itself. The staged value is
    deliberately **not** added yet — a writer may emit one only once the fleet
    is running a build that can read it.

    The `_apsk` and metadata arms carry no such hazard — neither changes what
    authenticates — which is why the advertisement path step 18 needs is
    usable as it stands.

12. **No at_onboarding_cli app can set any posture flag**, so "app-settable"
    is false for the whole CLI fleet. `AtOnboardingPreference extends
    AtClientPreference` and declares **no constructor**
    (`at_onboarding_cli/lib/src/util/at_onboarding_preference.dart:6`), so it
    inherits the implicit no-arg one and every construction-final flag —
    `posture`, `disallowLegacyEncryption`, and now `inUseSigningAlgorithms`
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

13. **`SigningAlgoType` is not reachable from at_client's barrel, so naming an
    in-use signing algorithm needs a second import.** An app writing
    `AtClientPreference(inUseSigningAlgorithms: {SigningAlgoType.mldsa65})` must
    import `package:at_chops/at_chops.dart` as well as at_client. Verified by
    probe 2026-08-13: a test importing only `package:at_client/at_client.dart`
    fails to compile on the name.

    **Left as is, deliberately**, and recorded so the next reader does not
    re-derive it as a defect: the two SigningAlgoType-valued knobs already on
    the preference — the deprecated `signingAlgoType` and
    `ReleasePosture.retrofitAuthenticationAlgo` (named `retrofitSigningAlgo`
    until row B1) — have always required that import, so
    exporting it now would be a new inconsistency rather than a fix, and a
    barrel export is public surface that cannot be withdrawn. `SigningRollout`,
    the axis an app is more likely to name, **is** reachable (it lives in
    `release_posture.dart`, which the barrel exports). If this is revisited,
    the precedent is `EnrollmentKeyExchangeMode`, show-narrowed onto the barrel
    for exactly this discoverability argument
    ([`decisions.md` 70](decisions.md#70-workstream-a-capstone-releaseposture-the-five-flags-as-one-value-2026-08-10)).

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
    2026-08-17 [14.32](../implementation-plan.md#1432-a-primary-clients-ml-dsa-signing-key-is-not-visible-to-its-verifiers)
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
      ahead of the keyfile's retired set while `AtKeys.retiredSigningKeysFor`
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

23. **A released `version: 1` keyfile holding an empty `keys` array is now
    refused, and nobody has named a holder.** `AtKeys.fromJson` throws on
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

#### 14.19.1 Things that LOOK like defects and are not

Recorded because each was proposed as a fix and **rejected on evidence**.
Without this note the next reader re-derives the proposal, "fixes" it, and ships
a false claim — one of them was already drafted into a CHANGELOG line before an
adversarial pass killed it. Items 1–3 came from ruling 6; the rest were raised
later, so do not read this list as scoped to one ruling. **Add to it rather
than re-litigating an entry**, and if an entry is genuinely wrong, amend it in
place with what it used to say.

0. **Do NOT add a "refuse a document carrying a top-level `atSignKeys` by
   name" guard.** Proposed 2026-08-15 while renaming that field to
   `atsignKeys`, on the precedent of A1's refusal of a stale top-level `keys`
   (which is a real guard and stays). ⚠️ **The two cases are not alike, and
   the difference is who holds the stale document.** A1's `keys` guard protects
   against a shape *this tree itself wrote and shipped through several of its
   own commits*, so a stale file could plausibly be sitting on a machine that
   matters. `atSignKeys` existed only between A1 and this rename, was never
   released — zero matches across all ten at_auth versions in the pub cache,
   with `class AtKeys` as the positive control — and the only files carrying it
   are ones our own functional runs generate and regenerate. gkc ruled it out
   the same day. A guard here would be code no reachable file can trigger,
   which reads as a supported migration path that does not exist.
1. **A corrupt-base64 pairwise envelope is NOT misclassified as transient.**
   It is tempting to read `sweepOnce`'s broad `catch` arm as the "retry
   forever" path and the `received == null` arm as the "deterministic skip"
   path, and to claim routing the decode through `pqOpenFromBase64` changes the
   outcome. It does not: both arms run the same two statements — release the
   claim, log a warning — and neither deletes, so the envelope waits for ttl
   expiry either way. Only the log line and the classification differ. Do not
   describe this as a behaviour or at-rest change.
2. **An `on PqSealException` arm at the nskey seal site would be dead code.**
   `pqSeal` throws it in exactly one place, the unsupported-version refusal,
   and `NskeyProvider.encrypt`'s own version guard makes that unreachable — the
   version always comes from `sealVersionFor`. The wrong-length-key case that
   arm looks like it catches arrives from `encapsulate`, which at_chops now
   maps itself.
3. **Do NOT tighten `_openIfSymmetricKey`'s `catch (e)` to a typed catch.**
   `enrollment_symmetric_key.dart` documents "every rejection is a skip rather
   than a throw", its caller's poll loop has no `try` at all, and a throw there
   fails the whole enrollment — recoverable only by re-requesting, since the
   conveyed `apkamSymmetricKey` is written once. The breadth is the contract.
   [Section 47.6](decisions.md#476-two-defects-in-the-enrollment-path-both-from-the-same-shape)
   records the two defects that breadth was introduced to fix.
4. **A suite-versus-key-algorithm guard in `_consume` would change no
   outcome.** Once a client can hold keys under more than one KEM
   ([14.18](#1418-the-remaining-d1-initial-development-sequence) step 5), an
   envelope can name an ML-KEM suite and an X-Wing key, and it looks like
   something to refuse before the open. It is not: at_chops maps the
   wrong-length secret key to a `PqOpenException`, which the open already
   catches and skips, and its message names the mismatch outright
   ("ML-KEM-1024 secret key must be 3168 bytes: 32"). The guard was written,
   removing it turned nothing red, and it comes out — a check that changes no
   outcome and reads like a security check it is not. What *does* matter is
   pinned instead: the envelope is skipped rather than crashing the sweep, so
   the good envelopes behind it in the batch still arrive.
5. **Do NOT add `atKeysIo ??= KeychainAtKeysIo()` to at_client_flutter's
   `AuthService.authenticate()`.** `onboard()` has exactly that line
   (`auth_service.dart:40`) and `authenticate()` does not, which reads as an
   oversight and is not. `AtAuthRequest`'s constructor already refuses a
   request carrying neither `atKeysIo` nor `atAuthKeys`
   (`at_auth_requests.dart:119`), so on the authenticate path the `??=` could
   only ever fire when the caller supplied **`atAuthKeys`** — an app that
   loaded its own key material and is telling you so. Defaulting a keychain
   source there points the client at a store that may hold another atSign's
   keys, or none. The asymmetry is correct: onboarding *mints* keys and needs
   somewhere to write them, while authenticating does not. Proposed and
   rejected 2026-08-13 while wiring [14.18](#1418-the-remaining-d1-initial-development-sequence)
   step 11; the same reasoning is now a comment above the method, because the
   invitation is in the file rather than in this document.
6. **Do NOT add `update` to at_client's `EnrollmentService`.** The invitation is
   strong and will recur: `AtEnrollment.update` landed with no at_client-side
   entry point, `EnrollmentServiceImpl` already wraps an `AtEnrollment`, and it
   already forwards `approve`/`deny`/`revoke` — so exposing `update` beside them
   looks like finishing the job. It is not. That facade is the **approver** side:
   every verb on it needs a connection holding `__manage` and acts on *somebody
   else's* enrollment. `enroll:update` is the opposite — no privilege at all, and
   only ever on the enrollment the connection *is*, with the atServer refusing an
   owner connection rather than waving it through. Putting both behind one
   interface makes the two authorities look interchangeable to every caller and
   every reviewer, which is the distinction the whole self-only security argument
   rests on. Note also that the facade does **not** mirror `AtEnrollment` today —
   it carries no `submit`, no `list`, no otp verbs — so "it forwards the others"
   was never the rule. Proposed and rejected 2026-08-13 while landing
   [14.18](#1418-the-remaining-d1-initial-development-sequence) step 16. When
   steps 17–18 need to reach `update` from at_client, give it a seam of its own
   on the signing path rather than widening this one.

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
| A1 | ✅ **DONE 2026-08-14.** `AtKeysMaterial`/`AtKeys` parse+encode moved to `enrollments[]` and `atsignKeys[]`; keyIds normalise to `<role>:<algo>:<gen>` and drop the embedded enrollment id; `status` stays explicit; `AtKeysMaterial` keeps `enrollmentId` in memory, populated from the container. The accessors split by scope per [`decisions.md` 100](decisions.md#100-the-seven-shapes-ruling-99-left-open-2026-08-14) ruling 2 — every one of the six production call sites outside at_auth was atSign-scope. `activeEnrollmentId` is gone, replaced by `enrollmentIds` / `authenticatableEnrollmentIds` / `resolveAuthenticatingEnrollment()`, which throws rather than picking when several qualify. **Two things the suites caught that reading did not:** the key-package pairing collected public halves document-wide, so under `(enrollment, keyId)` one enrollment's published address could vouch for another's private half; and an rsa2048 retrofit files under `auth:rsa2048:1`, which a blanket rename to `auth:mldsa65:1` got wrong. A `version: 1` document carrying a top-level `keys` is now refused **by name** — a judgement this row made, not a ruling: `keys` is no longer reserved, so parsing one would sweep its material into `metadata` and authenticate from the flat block as the legacy enrollment. Rails: at_auth **298/298**, at_client **1265** (2 skipped), acceptance **57** (2 skipped), at_onboarding_cli **39/39** | Everything else files material. This is the container |
| A2 | ✅ **DONE 2026-08-14.** The single-active-authentication rule moved from `validateKeyMaterials` (read) to a new `AtKeysAssurance.refuseSecondLiveEnrollment` (write), which only `AtKeys.addKey` calls. **The rule had to be moved, not deleted, and the reason the reader inherited it is worth keeping:** `fromJson` built the document by calling `addKey` for every material, so read and write validation were literally the same code path. A private `AtKeys._parsed` now files through `_file` — the structural invariants without the write-only policy. The refusal also got stricter where it moved: it is owner-agnostic and algorithm-agnostic, so one enrollment holding `auth:rsa2048:1` and `auth:mldsa65:1` both active is refused, which the per-(role, algorithm) rule structurally cannot see. Pinned in `plural_enrollments_test.dart` — reads, round-trips both enrollments on flush, refuses to name one, serves a caller that names its own, and the write path still refuses. **Proven by mutation**: making `_parsed` file through `addKey` again turns exactly the four read-tolerance tests red and leaves the writer-refusal test green. Rails: at_auth **304/304**, at_client **1265** (2 skipped) | Reader-first. A reader that refuses a second entry makes plurality unenableable later — the `.single` lesson |
| A3 | ✅ **DONE 2026-08-14.** Seven generated keyfiles carrying the old typed shape were deleted from `tests/at_functional_test/test/testData/` (`@colin`, `@jeremy`, `@xavier`, `rf2b-legacy`, `rf2b-t1`, `rf2b-t5`, `rf2d-posture`); all seven were untracked and regenerable. **The correction below held exactly**: the two tracked fixtures, `@alice🛠_key.atKeys` and `@bob🛠_key.atKeys`, are legacy-flat with no `version` at all and parse unchanged. ⚠️ **Corrected 2026-08-14:** an earlier draft of this row said the *tracked* fixtures are version-1 old-typed and become unreadable. They are not — and `build_test_atkeys.dart` files no typed material. Only keyfiles a *live retrofit* produced carry the old typed shape, and those are generated, not tracked. ⚠️ **All seven are back on disk, and that is the proof rather than a regression**: the functional run that followed regenerated them in the NEW shape (`version: 1`, `enrollments[1]`, no top-level `keys`), which is the container being written and read by production code against a real atServer |
| B2 | ✅ **DONE 2026-08-14 — and it moved ahead of B1, see the note below this table.** `apskEntries` now advertises the active signers plus the enrollment's **retired signing keys**, and the APKAM authentication key only while it *is* the signer — never retained. A new `AtKeys.retiredSigningKeysFor` supplies the retired entries **public-only** (a retired key must never sign again) and does **not** require the private half to still be present, so a build that wipes withdrawn private material cannot silently withdraw the advertisement with it. Selected on exactly `KeyPartStatus.retired`: `dead` was never adopted, and an unknown status is skipped rather than guessed at. Reached through a new `ApkamSigning.retiredSigningKeys`, which — unlike `heldSigningKeys` — is **not** filtered by `canSignEnvelopeWith`, since these entries exist for *other* parties to verify with and dropping one on a fact about the publisher would unverify its envelopes for every reader that could have handled them. `SigningKeyMinting._publish` re-reads them rather than assuming none, because that publish rewrites the whole record. **Proven by two symmetric mutations**: gutting `retiredSigningKeysFor` to empty reddens exactly the two retained-signing-key tests, and removing the dedup reddens exactly the third. Rails: at_auth **304/304**, at_client **1268** (2 skipped), acceptance **57** (2 skipped), functional **163/163** — the last one being the only thing that could say a live advertisement still reads | Must precede any writer that mints a signing key, or rollout 1 publishes an array |
| B1 | ✅ **DONE 2026-08-14, together with D2 — see below.** `SigningRollout` gained `defaultRetrofitAuthenticationAlgo` (`now` → `rsa2048`, `rollout1`/`rollout2` → `mldsa65`) and its in-use sets became `{}` / `{rsa2048}` / `{mldsa65}`. `retrofitSigningAlgo` is renamed `retrofitAuthenticationAlgo` **and is now a derived getter**, so both named constructors lost an argument — [98](decisions.md#98-rollout-1-moves-the-authentication-key-not-the-signing-key-2026-08-14) ruling 6, "two stored fields would be two controls over one position". **One defect this surfaced:** `selfRetrofit` read `preference.posture.retrofitSigningAlgo`, i.e. the *posture's* stage, so an app setting `signingRollout: rollout1` beside a migration posture would have retrofitted under `now`'s algorithm and said nothing. It now reads `preference.signingRollout`, which is the effective stage. Rails: at_client **1269** (2 skipped), functional **163/163** | 98's stages are defined here. Everything downstream reads them |
| B3 | ✅ **DONE 2026-08-14, both halves.** `selfRetrofit` mints a fresh RSA-2048 signing keypair before submitting and hands it to both the request and the key-package builder; at_auth advertises it as `apskLegacy` (bare), files it under `sign:rsa2048:1`, and signs the key package with it per [98.3's amendment](decisions.md#983-where-the-signing-key-comes-from). The seam is an explicit `EnrollmentRequest.advertisedSigningKey`, supplied by the caller because holding a signing key is a rollout position and at_auth cannot see a preference; absent, every path behaves as before, which is what keeps `now` unmoved. `SigningRollout.mintsOwnSigningKey` derives from the in-use set being non-empty rather than being listed again. **The greenfield-onboard half followed the same shape**: `makeActivationPqNative` mints the rsa2048 signing keypair, sets it on `AtOnboardingRequest.advertisedSigningKey` **and** hands the same pair to the key-package builder; `AtAuthImpl` carries it into `FirstEnrollmentRequest` and files it after the atServer assigns an id. **Proven by six mutations in all, each reddening only its own tests**: in the retrofit half, ignoring the advertised key in `_apskFor`, dropping the filing, and signing the package with the APKAM key; in the onboard half, dropping the request field, which reddens all three onboard pins. Rails: at_auth **307**, at_client **1273** (2 skipped), functional **163/163** | ⚠️ **B3 is one commit, not two.** Splitting it publishes an ML-DSA array at enrollment creation — the breakage rollout 1 exists to prevent, landing on peers who cannot fix it |
| B4 | ✅ **DONE 2026-08-14.** The role is recorded on `SigningKeyMinting` itself — what reaches it is an enrollment created before enrollment-time minting, or a client whose in-use set has changed since the last start — and the defect this row was carrying is fixed. **The defect, measured rather than read before it was fixed:** the heal path always published the **array**, because `_publish` sent `EnrollmentUpdateRequest(signingKeys: …)` with no branch and `EnrollmentUpdater` prefers `signingKeys` over `apskLegacy`. A rollout-1 client healing a pre-B3 enrollment therefore advertised a one-entry JSON array where [98.1](decisions.md#981-the-stages) requires the bare RSA string every deployed consumer base64-decodes — the breakage rollout 1 exists to prevent, arriving from the second writer while the first one obeyed the rule. The bare-versus-array rule now has **one** definition, `bareApskValueOf`, and the enrolled path uses it to choose which *field* carries the advertisement. Pinned in both directions: a mutation making everything bare reddens 7 rows, and the row for the bare form was written first and watched fail. ⚠️ **Whether the atServer honours `apskLegacy` on an `enroll:update` was a claim about the server, not the client** — it had only ever been sent on the enrolment request — so it is measured live in `tests/at_functional_test/test/apsk_server_side_test.dart`, "a healed enrollment advertises its signing key in the bare form", which drives the real writer and reads the record back with a control proving the enrollment held no signing key beforehand | Follows B3 |
| B5 | ✅ **DONE 2026-08-14.** `SigningKeyMinting.mintMissing` became `reconcileSigningKeys`: it computes *held − wanted* beside *wanted − held*, publishes the post-move advertisement, files the addition and then the withdrawal, and returns both lists. New `AtKeys.retireSigningKeys(enrollmentId, algorithm)` moves both halves to `retired`, selected on the `sign:<algo>:<n>` shape rather than the `privateSigning` role — the role is shared by the atSign's signing root and by any other material an enrollment signs with. **Three orderings the row did not name, each found by asking what it routes into:** the publish must be *handed* the keys being retired, because the keyfile still holds them as active at that point and a re-read would drop them from the advertisement entirely rather than move them to `retired`; the withdrawal is filed *after* the addition, or there is a moment with no active signing key where `signingKeys` falls back to an authentication key the advertisement has stopped naming; and an empty in-use set retires **nothing**, since that is the released posture rather than "every algorithm has left the set". **The stage-transition test the row asked for is `signing_key_minting_test.dart`, group "a stage transition"** — eight rows, including an envelope signed at rollout 1 that must still verify against the rollout-2 advertisement, run on the no-enrollment arm so the pin reads the `_apsk` value this client actually published. **Proven by three mutations, each reddening only its own rows**: dropping the retirement (5 red), publishing without the retiring keys (2 red, one of them the envelope, failing with "no algorithm in common"), and restoring the old early return on an empty *missing* set (1 red). A fourth, in at_auth, dropped the keyId shape filter and reddened exactly the row about it — ⚠️ **after a first attempt at that row was itself red for a fixture reason**: it gave one enrollment two active `privateSigning` keys of one algorithm, which `addKey` refuses, so the mutation "reddened the right test" while proving nothing. Rails: at_auth **312**, at_client **1281** (2 skipped), acceptance **57** (2), at_onboarding_cli **39** | Required before rollout 1 → 2 works at all; not required for rollout 1 |
| C1 | ✅ **DONE 2026-08-14.** Asking for a client that already exists with a preference naming different rollout axes throws an `ArgumentError` naming **every** differing axis, through one static `AtClientImpl.refuseChangedRolloutAxes` and a new `AtClientPreference.rolloutDifferencesFrom`. ⚠️ **The row named one site and there are THREE** (this said "two" until the wrap-up, which is the count-not-the-list trap again — the third was appended in the sentence below instead of correcting the headline): `AtClientManager.setCurrentAtSign` short-circuits a same-atSign call carrying no override argument and returns **without calling `create` at all**, which is the ordinary path — so a guard on the cache alone would have been loud only where a caller happens to pass an `atKeysIo`/`atLookUp`/`enrollmentId`, and silent everywhere else. All three check; three mutations, one per site, prove none stands in for another. **Two shapes the ruling did not state, both found by the caller sweep before writing the guard:** the comparison is by **value**, never identity — the e2e pack builds a fresh preference for every `setCurrentAtSign`, so an identity test would refuse every one of them — and the **posture is compared by what it means**, not as an object, since `ReleasePosture` declares no `==` and only `const` instances are canonicalized, so `ReleasePosture.migration()` written without `const` would be refused over a difference that does not exist. Rails: at_client **1297** (2 skipped), functional **164/164**. ⚠️ *This row said **1296** until the wrap-up: that figure was written before the `setPreferences` door was built, and never re-measured after it. 1281 (B5) + 1 (B4's bare-form row) + 15 (this row's new file) = 1297, which is what two runs at `aa9f5ea55` printed.* ⚠️ **A third door was found and gkc ruled it shut the same day:** `AtClient.setPreferences` replaces the whole preference on a running client, so leaving it unchecked would have made the other two a check in appearance only. Naming the replacement does not make the change possible — the substrate reads these axes at a startup that has already run, so accepting them would leave the client *reporting* a stage it never applied, which is worse than the silent drop, where the caller at least kept the stage it was running under. Everything outside the rollout axes is still replaced. One call site in the tree (`tests/at_functional_test`'s `TestUtils`, which passes the object it just built), so the live pack measures it on every init | Independent of A and B; can land any time. Do it early — it is what makes a mis-wired stage loud instead of silent |
| C2 | ✅ **DONE 2026-08-15.** `PqClientBootstrap._reconcileEnrollmentSnapshot`, a new **last** step — nothing reads the snapshot, so it can only delay a step that heals key material, never enable one — writing through `WrittenAtKeysIo.update`. ⚠️ **The row's scope was one guard short, and it is the guard that matters: the snapshot is recorded only for an enrollment the keyfile ALREADY HOLDS.** `recordEnrollmentSnapshot` creates the slot when it is missing, and `AtKeys.toJson`'s `hasTypedContent` is `_enrollments.isNotEmpty \|\| _atSignMaterialsByKeyId.isNotEmpty` — so reconciling an enrollment with no material rewrites a legacy-flat keyfile as a `version: 1` document purely as a side effect of having opened it, which is the one thing that serializer's own comment exists to prevent. [decisions 100](decisions.md#100-the-seven-shapes-ruling-99-left-open-2026-08-14) ruling 6 asks C2 to *fill* snapshots, not convert keyfiles. **It shares `LocalSecondary`'s memoised fetch rather than issuing its own `enroll:fetch`** — one record described by two readers is two chances to disagree, and the record was already being read on the authorization path. A non-String grant value is **skipped, not stringified**: `'42'` recorded as an access level reads as a grant. A changed `namespaces` logs at `warning`, but only when there was a previous value to differ from — the first fill on a retrofit's keyfile is not a change, and logging it as one cries wolf on every such file. **Proven by mutation: disabling the slot guard reddens exactly one row of 14.** Rails: at_client **1302** (2 skipped), functional **164/164**, analyze exit 0 | ⚠️ Must use the store's atomic verb. This tree has already lost key material to two unawaited start-time writers doing read-mutate-write on this file. **Read from at_server `6a86fbcc` — do not re-derive:** `enroll:fetch` returns `{appName, deviceName, namespace, encryptedAPKAMSymmetricKey, status}`, where **`namespace` singular holds the whole `namespaces` MAP**, and a caller may always fetch its own enrollment |
| D1 | ✅ **DONE — the tail closed 2026-08-15.** `SigningRollout.rollout1` ("deliberately identical to `now` in what this client writes") and `selfRetrofit` ("no ML-DSA anywhere") were corrected in B1's commit, along with the two `ReleasePosture` constructor dartdocs, which carried the same claim in a third form. `signingAlgo` now states that it names the **authentication** key's algorithm — the key that signs the `from:` challenge — and not the algorithm the enrollment signs documents with, which is the one thing its name gets wrong. ⚠️ **The row named `EnrollParams` and there are THREE declarations**, which is this row's own right-hand warning coming true: `EnrollVerbBuilder` carried the identical sentence and `PkamVerbBuilder` — the verb where the field can ONLY mean the authentication key — carried none at all. | ⚠️ `design.md` carried the same errors and was banner-flagged 2026-08-14 — but a bare copy of the rollout-1 claim survived two paragraphs above the banner until the doc sweep. One correction does not find the others; grep the claim, not the file |
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
`inUseSigningAlgorithms` whenever the caller does not set it
(`at_client_preference.dart:111`) → B1 makes that `{rsa2048}` →
`PqClientBootstrap`'s `mintInUseSigningKeys` gate defaults **true**
(`pq_client_bootstrap.dart:43`) → `mintMissing` (B5 renamed it `reconcileSigningKeys`) returns early only on an empty
set (`signing_key_minting.dart:69`) → it mints an RSA signing key → `_publish`
calls `apskEntries`, which under the pre-B2 rule appends the auth key as
`retired` → two entries → `apskValueOf` emits the **JSON array** that every
deployed reader base64-decodes as an RSA key and fails on.

The matrix's `current/` arm reaches it: it sets `signingRollout` and
deliberately leaves `inUseSigningAlgorithms` unset, and attaches a persisting
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
  materials, each carrying `keyAlgorithmType`, `createdAt`, `status` and
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
| 2 | ✅ **DONE 2026-08-15.** `keyIdPrefix` became `keyIdRole` + `keyIdPrefixFor(algorithm)`, and the **parse moved down to at_auth**: `AtKeys.isRoleKeyId(keyId, role)` is algorithm-blind and is what `signingKeysFor` already used privately, so the `<role>:<algo>:<generation>` grammar has one home instead of a reader in at_client agreeing with a writer in at_auth by hand. `AtKeys.keyIdPrefix(role, algorithm)` composes it, and at_auth's own five sites now go through it. ⚠️ **The row named three things it routes into and there was a fourth: the three `KeyAlgorithmType.mlDsa65` literals on the MATERIAL** in `store` and `_storeFreshPair` — a slot id composed from one vocabulary while the material it holds is filed under another. Both now come from `rootKeyAlgoToken`, pinned against `KeyAlgorithmType.mlDsa65`. ⚠️ **And the before-grep understated at_auth: a filtered grep showed one caller of the private parse and an unfiltered one showed three.** Proven by mutation: restoring the algorithm-specific prefix reddens exactly one test, the new one | ⚠️ Routes into `_freeSlot`, `nextAtSignGeneration('root', …)` and the `PqSigningRoot.keyIdPrefix` pin in `wire_literal_pins_test.dart`. That pin is **at-rest** so it moves with the id; the record-*name* pin beside it does not move |
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
| 1 | ~~A **remote-only** read of the published advertisement for the mint path. ⚠️ **NOT by changing `currentPublic`** — that is also the sender path, reached from `CkManager.ensureCurrent` on *every* put, so making it remote puts a round trip on the write path and breaks offline writes. A separate read, always remote, skipping both caches — the shape `PqSigningRoot.publishedRoots` already has | a sibling enrollment publishes; this client's pre-check sees it without waiting for sync. ⚠️ **Scope: `published_nskey_key_ring.dart:450` is the read to change, but it is NOT the only optionless read in the subsystem** — `ck_manager.dart:248` and `symmetric_aes_gcm_provider.dart:250` are optionless too. Those two are **content-key conveyance** reads rather than advertisement reads and are plausibly correct as local-first, so they are out of scope *by argument, not by absence*. Re-derive before believing either way: `git grep -n -A3 "atClient\.get(" -- packages/at_client/lib/src/crypto/nskey/`~~ ✅ **BUILT.** `PublishedNskeyKeyRing.publishedAdvertisement` is the new read; `currentPublic` is untouched. Three mint-path call sites use it — `mintAndPublish`'s post-loss read, `rotate`'s precondition, and `NskeySeeding.seed`'s pre-check |
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

**D1 initial development ends at step 34** — the spike carved into stacked PRs
and merged. Publishing and R-2 follow it and are not D1.

### 15.1 Open work — re-derive before acting

| # | What is owed | Owner | State |
|---|---|---|---|
| 1 | ✅ **14.22 is COMPLETE — all seven rows landed 2026-08-15** | [14.22](#1422-making-the-signing-root-rotatable--decisions-101) | Row 6 made the record mutable behind `_rootlock@<atSign>` and generalised `NskeyMintLock` into `MintLock`; row 7 proved the boundary and needed no new mechanism, only the composite scenario. **`decisions.md` 101 is fully built.** Nothing in this row is owed. ⚠️ **Step 27 (row 5) has since landed too**, 2026-08-15, and it was the right one to take first for the reason recorded there: it changed the signed bytes, so everything signed after it is signed under the shape that stays |
| 2 | **Step 20's rotation arm** — enrollment then an `enroll:update` APKAM rotation mid-run | [14.18](#1418-the-remaining-d1-initial-development-sequence) step 20 | ⛔ Blocked on an **at_auth release** carrying the tolerant reader, then the staged status value. Needs its own CRAM atSign |
| 3 | **Step 24** — a client with no enrollment id is treated as fully privileged | [14.14](#1414-a-client-with-no-enrollment-id-is-treated-as-fully-privileged) | Open; **wants a ruling** on whether an owner-keys client belongs in the enrollment trust model |
| 4 | **Step 25** — a `mintLegacyMaterial:false` atSign cannot write a public record | [14.12](#1412-a-mintlegacymaterialfalse-atsign-cannot-write-a-public-record) | Open. Gates the stop-release: closing it means public-record signing moves to the ML-DSA root and self data moves off `selfEncryptionKey` |
| 5 | ✅ **Step 27 — DONE 2026-08-15.** Domain separation on the signed envelope | [14.8](#148-domain-separation-on-the-signed-envelope) | Landed: per-use `EnvelopeType` in the protected header, `expecting` at both verify entry points, `at-root-link:` on the root link's signed bytes, and the re-anchor that change forced. [`decisions.md` 103](decisions.md#103-an-envelope-says-what-it-is-for-and-a-verifier-says-what-it-wants-2026-08-15) |
| 6 | **Step 28** — NoPorts carries its own copy of the envelope shape | [14.7](#147-noports-carries-its-own-copy-of-the-envelope-shape) | Open. A separately-owned second migration to *name*, not to fix here |
| 7 | **Step 29** — four audit residuals | [14.16](#1416-four-residuals-the-issue-tree-audit-surfaced-2026-08-09) | Open: perf ceiling on real low-end hardware, UC-A3.4 live self-direction, SS-4 interrupted-mint resume, IS-1 record-name drift |
| 8 | **Step 30** — `deprecated_member_use` across the workspace | [14.11](#1411-deprecated_member_use-findings-across-the-workspace) | Open. A call-site migration, not a lint sweep |
| 9 | **Step 31** — pre-PR rails checklist | [14.15](#1415-pre-pr-rails-checklist) | Open |
| 10 | ✅ **D1's tail — DONE 2026-08-15.** `signingAlgo`'s dartdoc in at_commons | [14.20](#1420-building-rulings-98-and-99--the-sequence) row D1 | Landed on **three** declarations, not the one the row named: `EnrollParams`, `EnrollVerbBuilder` and `PkamVerbBuilder`. at_commons **517/517**, re-run at this state rather than carried forward from `224460d8b` |
| 11 | **14.19's open small items — 11 unstruck, of which item 15 is resolved and kept only for its findings, and items 20–22 are examined-and-deliberately-left rather than work.** ⚠️ *This cell said **18** until 2026-08-18, against an actual 10-then-11; re-derive it with the command below rather than reading either number.* ✅ **Item 15 (the `_apsk` third writer) is EXAMINED, RULED and CLOSED** (2026-08-15) — do not pick it up. Re-derive the count rather than trusting it: `awk '/^### 14.19 /,/^#### 14.19.1/' docs/projects/pq/detail/implementation-plan.md \| grep -cE "^[0-9]+\. \*\*"` — ⚠️ **this named the LIVE file until 2026-08-18**, where the list does not live, so it printed `0` and exited 1, which reads as "no open work". That exact bug was found and fixed in the plan's own state block on 2026-08-16; this second copy survived the fix, which is why a re-derivation command gets grepped for rather than corrected where you found it | [14.19](#1419-small-items-raised-2026-08-12-and-not-yet-acted-on) | Open. **Item 8 is the only one waiting on a ruling** (typed key material is not self-encrypted at rest while the flat fields are). Item 10 is an unexplained functional run with two disproven theories. Item 14 is not PQ at all |
| 12 | **The nskey mint elects a winner** — one record, the lock becomes an election token with a cooldown, and only one of several enrollments that all decide to mint eventually does | [14.24](#1424-the-nskey-mint-elects-a-winner--decisions-105) | ✅ **DONE 2026-08-16**, all seven rows, **in D1**. The at_server fix rows 3 and 5 needed merged as [PR #2751](https://github.com/atsign-foundation/at_server/pull/2751) (`00c2f9a6` on trunk) — ⚠️ merged is not deployed: `at_virtual_env:local` runs it, `virtualenv:vip` does not. ⛔ **[14.23](#1423-per-generation-nskey-records--decisions-104-rejected) is REJECTED** — do not build it. Re-derive: `git grep -n "nskeyMintLockKey\|withLock" -- packages/at_client/lib` |
| 13 | **Steps 32–34** — carve into stacked PRs, merge to trunk | [14.18](#1418-the-remaining-d1-initial-development-sequence) | ⛔ Blocked on the **published atServer image verifying ML-DSA PKAM**. This gate touches step 32 **only** — nothing above it waits. The spike branch itself never merges |

**Not owed, and worth stating so nobody re-opens them:** step 11 is labelled
`PARTLY DONE` but its own cell closes with `✅ DONE 2026-08-13, with step 12` —
the **label** is stale, not the work. Step 23 folded into the rollout axis.
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
awk '/^### 14.19 /,/^#### 14.19.1/' docs/projects/pq/implementation-plan.md \
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

The release programme, in order, and **not** part of D1 initial development:
publish **at_chops 3.6.0** → **at_commons 5.16.0** → **at_auth 3.4.0** →
**at_client's GA minor** → **R-2**, the 4.0.0 posture flip (a pure
default-flip: 4.0 is identical to final-3.x *code*).

⚠️ Check pub.dev against every touched pubspec before acting on that ladder —
a same-value version bump merges silently.

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
- **B-1** owes everything beyond envelope delivery (`pushSecretToNames…`), a
  unit fixture that backs local storage and the atServer with **one map** so it
  cannot see a local-first-vs-remote-first defect on the read side, and
  UC-A3.4's self direction — owed rather than blocked since `ConcurrentClients`
  landed ([#2093](https://github.com/atsign-foundation/at_client_sdk/issues/2093)).

**The general finding, which is why this is worth a body.** Every wrong entry
was wrong in the *safe-looking* direction: three claimed work was owed that had
since been done. A stale "owed" reads as conservative and costs a rebuild;
`_getSigningAlgoType` is the sharp case, because the tree contradicted it
loudly — a passing live suite — and the contradiction sat unexamined because
nothing reads a project entry when a test goes green.

### 14.33 CLOSED: the `shared_key.*` refusal was never reachable

Raised by [14.31](../implementation-plan.md#1431-a-refused-watermark-write-permanently-disables-the-monitor)
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
[14.35](../implementation-plan.md#1435-notificationservicesend-throws-away-the-namespace-it-was-given).

**What is genuinely refused** is `NotificationService.send()` with a
single-segment namespace, which is [14.35](../implementation-plan.md#1435-notificationservicesend-throws-away-the-namespace-it-was-given)
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
