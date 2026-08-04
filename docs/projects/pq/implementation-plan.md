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
project works see [design.md](design.md); for the given/when/then acceptance tests see
[acceptance.md](acceptance.md); for the *why*/decision rulings see [decisions.md](decisions.md); for
the high-level trajectory see [roadmap.md](roadmap.md). No design detail, no key shapes, no
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
- [8. Phase R/B — rollout, rotation, retirement & versioning (R-1, B-2, B-3, ON-1, R-2)](#8-phase-rb--rollout-rotation-retirement--versioning-r-1-b-2-b-3-on-1-r-2)
- [9. Phase D2 — referenced only (D2-1, out of D1 GA)](#9-phase-d2--referenced-only-d2-1-out-of-d1-ga)
- [10. Cross-cutting: publish gates, critical path, waves/parallelism, testing](#10-cross-cutting-publish-gates-critical-path-wavesparallelism-testing)
- [11. Coverage map (D1 package / UC → project)](#11-coverage-map-d1-package--uc--project)
- [12. Open decisions pointer & verification provenance](#12-open-decisions-pointer--verification-provenance)
- [13. Phase IS — inter-server PQ authentication (IS-1)](#13-phase-is--inter-server-pq-authentication-is-1)

---

## 0. Purpose, scope & how to read this plan

This is the unified, plan-level backlog for D1. The project ids used throughout — `P-1/P-2/P-3`,
`S-1`/`S-2`/`S-3`/`S-5`/`S-6`, `SS-1a/b/c`/`SS-2`/`SS-3`/`SS-4`, `B-1`, `RF-1`/`RF-SRV`/`RF-2b`/`RF-2c`,
`R-1`/`R-2`, `B-2`/`B-3`, `ON-1`, `D2-1` — name the work as it lands in dependency order. Each project
entry is plan-altitude: a one-line Goal, what it **builds on**, a pointer to its deliverables in
[design.md](design.md), a pointer to its acceptance tests in [acceptance.md](acceptance.md), an effort
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
[design.md](design.md).

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
   ═══ CRITICAL PATH TO D1 GA ═══         ▼
                            B-1 the nskey DATA PATH (providers + marker + cold-start)
                                          │
                            R-1 migration machinery + disallowLegacyEncryption flag (default false)
                                          │
                            B-2 nskey rotation + revocation (B5/B6)  ◀── RF-1 + SS-3 (fan-out only)
                                          ▼
                         ▶ at_client 3.14.x = D1 GA (rebuild = reader, one flag = PQ writer)

   Off the GA critical path (parallel):
     RF-SRV server self-retrofit enroll → RF-2b PQ-APKAM mint + self-retrofit → RF-2c upgrade + e2e   (RF-1 confirm)
     B-3 selfEncryptionKey retirement (phases 1-3, needs at_server)     ON-1 PQ-native onboarding + legacy-interop flag
     S-5 at_auth 4.0 WASM split → S-6 consumer bumps          D2-1 at/pqmls carve + D1-E (D2)
     KF-1 .atKeys-at-rest protection + backup/restore (builds on S-3)
     IS-1 inter-server PQ auth (FROM/POL: swap challenge signature RSA→ML-DSA-65, PR #2683) — no KEM, no cert; builds on published at_chops 3.4.x (ungated)
     R-2 at_client 4.0 (flip flag default true) — final, gated on the ecosystem floor
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
**Deliverables → [design.md](design.md)** (at_chops primitives): residual only — confirm the stateless
functional surface and the deprecated shim both pass every X-Wing/GCM/HKDF/HMAC vector byte-exact, and that
`pqSeal`/`pqOpen` reuse `AesGcm256EncryptionAlgo`/`HkdfSha256` (no `package:cryptography` re-import). No
further publish required for P-1; the 3.3.0 slot is live.
**Acceptance → [acceptance.md](acceptance.md):** all vectors green via both surfaces; `pqSeal` round-trip /
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
**Deliverables → [design.md](design.md)** (at_chops primitives, ML-DSA): add an `mldsa65` branch in
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
**Acceptance → [acceptance.md](acceptance.md):** **algorithm-level** sign/verify (true) + tamper (false);
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
**Deliverables → [design.md](design.md)** (pqpublickey root key lifecycle): publish
`public:pqpublickey@<atSign>` (root, **never** `publickey.pq`); new enrollees prefer X-Wing-wrapping
`apkamSymmetricKey` to it; approvers accept RSA **or** X-Wing. ⚠️ the RSA-wrap lives in **at_auth** — add
at_auth to scope and bump its `at_chops` pin to `^3.3.0`. Freeze the `pqpublickey` **name + create-once
contract** as an interface-first artifact shared with SS-4 (which owns the create/seed/serve/pull lifecycle).
**Acceptance → [acceptance.md](acceptance.md):** enroll/approve conveys `apkamSymmetricKey` X-Wing-sealed
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

### S-1 — at_auth: extend `AtKeys` in place (additive PQ methods, deprecate legacy) + `AtKeysIo` runtime persistence (API only); publish 3.3.0 · at_auth · M — **SATISFIED and PUBLISHED — at_auth 3.3.0 is on pub.dev (verified 2026-08-03); no residual.** Consequence: at_auth has **no in-progress version open**, so the next change to it needs a new one opened
**Goal:** extend the existing `AtKeys` in place so it holds every key (per-enrollment AND per-APKAM) via
additive PQ-safe accessors while the legacy key fields deprecate; interface-first.
**Builds on:** at_auth `AtKeys`. Additive only; gates nothing in Wave 2.
**Deliverables → [design.md](design.md)** (structural design: extend `AtKeys`/`AtKeysIo` in place): keep the
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
**Acceptance → [acceptance.md](acceptance.md):** existing onboard/auth suites green; the extended `AtKeys`
PQ add→read→retire (material never removed; legacy fields still readable via the deprecated accessors);
`InMemoryAtKeysIo` round-trip (persistent round-trip proven once **S-3** wires the stores); unknown
`keyPartType`/`keyAlgorithmType` tokens round-trip unmodified.
**Effort:** M.
**Watch-outs:** ⚠️ **version** — resolved 2026-07-17: at_auth 3.1.1 published, then **3.2.0 was consumed by
the validateAtServer network-timeout release**; S-1 ships as **3.3.0** (Open decision #D closed). The
at_chops 3.4.x prerequisite (hashing-algo barrel exports) is satisfied — 3.4.0 published 2026-07-17.
**Publish state:** S-1 landed via PR #2047 (+ #2080 tweaks) and is published as **`at_auth 3.3.0-rc1`**.
The **rc1 → stable 3.3.0 promotion is an open gate**: S-6 (consumer bumps) and SS-2's at_auth work both
need a stable at_auth 3.3.0 to pin against, and consumers cannot depend on a prerelease without an explicit
prerelease constraint. Timing is unresolved — see [section 10](#10-cross-cutting-publish-gates-critical-path-wavesparallelism-testing).
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
**Deliverables → [design.md](design.md)** (CryptoProvider seam): add an `AtKeysIo keys` field to
`CryptoContext` (additive) — the provider seam is injected the `AtKeysIo` (the key source) and yields the
extended `AtKeys`; `CryptoRuntime` threads it into provider calls (ratified 2026-07-06, #2045 — see
[decisions.md](decisions.md)).
**Acceptance → [acceptance.md](acceptance.md):** existing crypto/legacy round-trips green; behaviour-neutral
(no wire/stored-value change); Mode-B regression retained.
**Effort:** S.
**Watch-outs:** ⚠️ **Scope cut** — keep ONLY the additive field; **defer** migrating `LegacyCryptoProvider`
to read from `context.keys` (legacy pulls remote `plookup`s + `atChops` cipher ops the 6 static fields
can't supply). This plan keeps `LegacyCryptoProvider` reading its own sources (additive-field-only) — see
Open decision #E in [decisions.md](decisions.md).
Resolve where `context.keys` is sourced at construction (overlaps S-3).
**coversD1:** D1-S S5.

### S-3 — at_client/at_auth: updatable `.atKeys`/keychain via the injected `AtKeysIo` · at_client, at_auth, at_client_flutter · L
**Goal:** durable, updatable key-storage homes (bootstrap→file/keychain, distributed/rotating→keystore,
ephemeral→memory). Stores are **dumb** — convergence stays in the substrate.
**Builds on:** S-1's extended `AtKeysIo` runtime-persistence API.
**Deliverables → [design.md](design.md)** (key stores): make `FileAtKeysIo` updatable (re-wrap the
self-encryption key on rewrite, atomic write + backup); compose the extended `AtKeys` (via its injected
`AtKeysIo`) at AtClient construction; cover the keychain store, which `flush()` alone does not reach.
`LocalKeystoreAtKeysIo` over the 5.x keystore is **out of scope** (2026-07-17 ruling).
**Acceptance → [acceptance.md](acceptance.md):** post-onboarding key add persists + survives close/reopen;
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
**Deliverables → [design.md](design.md)** (WASM barrel): move `FileAtKeysIo` + the `dart:io` socket probe
to a new `at_auth_io.dart` barrel; drop the `atKeysIo ??= FileAtKeysIo()` default (require injection);
registrar on `package:http`; publish 4.0.0.
**Acceptance → [acceptance.md](acceptance.md):** ⚠️ **narrowed** — assert the *at_auth-owned* sources
reachable from `at_auth.dart` no longer import `dart:io` and the default is gone. Do **not** gate on a true
`dart compile wasm` of the core (it still transitively reaches `dart:io`/`dart:ffi` via `at_lookup`/`at_chops`
— those WASM splits are a **separate effort out of the D1 crypto program**, the `wasm-port`). CLI/flutter
importing `at_auth_io.dart` compile + auth functional green (post-**S-6**).
**Effort:** L.
**Watch-outs:** `FileAtKeysIo` never leaves at_auth. **at_auth 4.0 (structural/WASM) is a different major at
a different time from at_client 4.0 (R-2, the flag flip).**
**coversD1:** D1-S S4.

### S-6 — Consumer constraint bumps onto at_auth `^4.0.0` · at_client, at_onboarding_cli, at_client_flutter, **tests/at_functional_test, tests/at_end2end_test** · M
**Goal:** consumers adopt the breaking at_auth major.
**Builds on:** S-5. Publish in dep order (at_chops → at_auth → at_client/onboarding/flutter → at_cli_commons).
**Deliverables → [design.md](design.md)** (WASM barrel consumer adoption): consumers adopt `at_auth ^4.0.0`,
importing `FileAtKeysIo` from `at_auth_io.dart` with explicit injection. ⚠️ the two **test packages pin
at_auth directly** — include them; `at_cli_commons` is a **transitive-only** bump (no direct at_auth dep,
no FileAtKeysIo use).
**Acceptance → [acceptance.md](acceptance.md):** each consumer + both test packages compile and pass against
`^4.0.0` with explicit injection; onboarding functional green.
**Effort:** M.
**Watch-outs:** sweep every inline `FileAtKeysIo()` site; `example/pubspec.yaml` `dependency_overrides`
needs at_auth added; use `melos bootstrap`.
**coversD1:** D1-S S6.

### KF-1 — `.atKeys`-at-rest protection + backup/restore · at_client, at_auth, at_client_flutter · L  *(new D1 scope, off the GA critical path — parallel)*
**Goal:** protect the PQ private material in the keyfile at rest and define a backup/restore story (including
the stale-backup case). Off the GA critical path — runs in parallel.
**Builds on:** S-3 (updatable `.atKeys`). Additive; gates nothing on the GA critical path.
**Deliverables → [design.md](design.md)** (keyfile at-rest protection + backup/restore): encrypt the PQ
private material at rest in the keyfile — the **X-Wing key-package private** and the **ML-DSA APKAM private**
— alongside the existing key material; define the keyfile **backup/restore** flow, including the
**stale-backup** case: a restored backup whose enrollment was **capped/expired by a retrofit** (RF-SRV) must
be detected and handled rather than silently authenticating with a dead enrollment.
**Acceptance → [acceptance.md](acceptance.md):** PQ privates unreadable at rest without the wrapping key;
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
[design.md](design.md) §2. **SS-0 landed the substrate baseline** (PR #2037, merged 2026-07-17) — SS-1c /
SS-2 / RF-1 all presuppose that code, and it is now on trunk.

**Shared substrate fact (stated once).** **pull** (`requestSecret`) and **push**
(`pushSecretToNamespaceMembers`) are **dual facets of one substrate**: the same `__ssenv` envelope sealed
to a key package via `pqSeal`, the same gated `enroll:listns` discovery, the same `SecretStore`
and `putIfNewer` ordering. The mechanics (kpid addressing, the `__ssenv` envelope shape, sign/verify,
`SecretStore`, push/pull primitives, the `enroll:listns` verb + `EnrollParams.metadata`, the
atServer enrollment record + the authenticated self-retrofit flow + expiry copy/cap) live in
[design.md](design.md). The given/when/then (UC-A2.x / A3.2 / B5.x) lives in [acceptance.md](acceptance.md).

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
   `{nskeyKid, publicKey}` envelope, **mutable** (rotation overwrites it, serialised by the short-ttl
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
**Acceptance → [acceptance.md](acceptance.md):** substrate unit suite green; the baseline compiles in the
1:1:1 shape with no write-path residue.
**Effort:** M.
**Watch-outs:** SS-1c / SS-2 / RF-1 cite PR #2037 as "already landed" — that prerequisite is now met.
**coversD1:** D1-F substrate baseline.

### SS-1a — at_commons enroll grammar: `EnrollParams.metadata` + flattened `listns`; publish 5.12.0 — **SATISFIED (at_commons 5.12.0 published 2026-07-04; grammar on trunk via #2040)** · at_commons · M
**Status:** SATISFIED — landed on trunk via #2040 (2026-07-04, with #2044 stacked in); at_commons 5.12.0 published to pub.dev.
**Goal:** publish the grammar the new enroll verbs need before any server can parse them.
**Builds on:** — (root). The key package rides `EnrollParams.metadata` (no grammar change); there is no
`enroll:metadata` op.
**Deliverables → [design.md](design.md)** (enroll verb grammar / `EnrollParams.metadata`): add the
`listns` op (inner alternative inside the single `(?<operation>)` group, leftmost-first before
`list`) + its `listNamespace` segment. Add `metadata` (opaque map) and `signingAlgo` (`rsa2048|mldsa65`)
fields to `EnrollParams` + the `EnrollVerbBuilder` cascade + `.g.dart` regen. Document the **flattened**
`listns` shape `[{enrollmentId, access, apkamPubKey, metadata}]`. Also widen the **pkam-verb**
`signingAlgo` literal (`ecc_secp256r1|rsa2048` → add `mldsa65`, consumed by the server at auth time — folded
into this publish, #D). Bump 5.11.0 → **5.12.0** + publish.
**Acceptance → [acceptance.md](acceptance.md):** `listns` parses (no `metadata` op); `EnrollParams`
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
**Deliverables → [design.md](design.md)** (atServer enrollment record): on `enroll:request`, persist
`enrollParams.metadata` + `signingAlgo` onto the enrollment record (`EnrollDataStoreValue` gains
`metadata` + `signingAlgo`; store a **single** `apkamPublicKey`). Add the gated `enroll:listns`
discovery (a new `_isAtLeastReadOnNamespace` gate) emitting the **flat**
`data:[{enrollmentId, access, apkamPubKey, metadata}]`; at_server_spec dartdoc; first live functional round-trip.
Also **keep `_apsk` present**: the atServer populates `public:_apsk.<eid>.<perEnrollmentApproved>@<atSign>`
from the record's `apkamPublicKey` (on approval / first authenticated use) rather than relying on the
client-side `publishPublicSigningKey`, and keeps its write-restriction — the presence + write-restriction
cross-tier property (design.md §2.4) that both envelope and advertised-key verification depend on.
**Acceptance → [acceptance.md](acceptance.md):** metadata stored verbatim + returned by `listns`;
**schema-migration test** (pre-`metadata`/`signingAlgo` record opens null, write round-trips); flat records,
≥r gate, approved-only, `*` wildcard; UC-A2.3 server discovery gate; an approved enrollment's `_apsk` is
fetchable without a client publish, and a cross-enrollment `_apsk` overwrite is refused; `runLocal.sh`
(compose-down, ≤180s) + **both** suites green.
**Effort:** L.
**Watch-outs:** ⚠️ the at_commons fields (SS-1a) must publish first; **the atServer-schema change must land in
the same release as the client**; check the enroll-record value-size limit accommodates a ~1KB key-package
blob; downstream client obligation = SS-1c.
**coversD1:** D1-F DEP1 (server) + DEP2.

### SS-1c — wire at_client to the live verbs + flattened parser · at_client, tests · M — [#2084](https://github.com/atsign-foundation/at_client_sdk/issues/2084) — **PARSER + VERIFY LANDED on `gkc-pq-d1-spike`; live drive still owed**
**Goal:** drive the live verbs and parse the flat shape.
**Landed:** the flat `listns` parser, and the advertised-key verification for **both**
keys — the published `nskey` (`ApkamSignedAdvertisedKeys`, proven cross-atSign live) and
the **key package** (`KeyPackageRegistration.signedKeyPackagePayload` /
`VerbEnrollmentDirectory`, unit-only). **Still owed:** no production call site issues
`enroll:listns`, so the key-package half has never met a live verb — that arrives with
SS-2's wiring.
**Builds on:** SS-0 (substrate baseline on trunk) + SS-1b.
**Deliverables → [design.md](design.md)** (`enroll:listns` client parser): rewrite
`VerbEnrollmentDirectory.listForNamespace` for the **flat** `[{enrollmentId, access, apkamPubKey, metadata}]`
shape (one `NamespaceMember` per enrollment, **singular nullable `metadata.keyPackage`** — no format-keyed
map, `KeyPackage.apkamId` from `apkamPubKey`). The key package rides `enroll:request` (SS-2); there is no
`registerKeyPackage` / `enroll:metadata` write path, interface decl, `register()` call site, or
`FakeEnrollmentDirectory.registerKeyPackage`. The `listForNamespace` dartdocs state the **1:1:1 single-key**
model. **Verify the advertised key package's APKAM signature** against the enrolling atSign's `_apsk`
(design.md §2.1 *Advertised-key authenticity*) before trusting it — the same verify path same-atSign and
cross-atSign; reject an unsigned / wrong-signer package.
**Acceptance → [acceptance.md](acceptance.md):** flat parse → `NamespaceMember` + decoded `KeyPackage`; a
signed key package verifies against `_apsk`, a tampered / wrong-signer one is rejected; **no
code path issues `enroll:metadata`**; the test-consumer sweep migrates all three suites off the `registered`
seam to a 1:1:1 seeding seam; a client-driven functional round-trip.
**Effort:** M.
**Watch-outs:** the `listForNamespace` parse unit test already exists (landed with the SS-0 baseline, PR
#2037) — don't duplicate it. Clear the test's own `.atKeys` and gitignore it.
**coversD1:** D1-F DEP1 (client parser) + DEP2 (write path removed).

**Progress (2026-08-03, `gkc-pq-d1-spike`).** **All six implementation steps are landed**, with the
whole chain proven live in `tests/at_functional_test/test/enrollment_key_package_e2e_test.dart`:
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
**Deliverables → [design.md](design.md)** (substrate production wiring + server wake-up): DEP4 `__ssenv`
update-put auto-notify (drop the rethrow; update-path only) + flip client self-wake-up off. **Production
wiring:** re-key the facade Expando to `(AtClient, enrollmentId)` (+ `enrollmentId`
on `forClient`); the X-Wing key package — **APKAM-signed via `wrapAndSign`** (design.md §2.1
*Advertised-key authenticity*) and placed at the singular `metadata.keyPackage` — rides into `enroll:request`
as the opaque `EnrollParams.metadata` (built by an at_client orchestrator *above* at_auth; at_auth ferries,
never interprets). **Conveyance is the
NEW-DEVICE approver path only:** an at_client approve-wrapper fires `shareAllSecretsWithEnrollment` after
at_auth's `approve` (seals an `__ssenv` envelope to the new device's key package). The **auto-approved
self-retrofit** (RF-2b/RF-SRV) needs **no conveyance** — the retrofitting client already holds its own
secrets locally. **ML-DSA APKAM auth:** the at_chops
verify branch (P-2) + the at_commons pkam `mldsa65` literal (in SS-1a's publish) + the server
`_getSigningAlgoType` ML-DSA branch reading the record's `signingAlgo`.
**Acceptance → [acceptance.md](acceptance.md):** one value-less `__ssenv` self-notify on update (none on
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
`enroll_verb_handler.dart`, so DEP4's update-put auto-notify is unbuilt; (2) `_getSigningAlgoType`
(`pkam_verb_handler.dart`) branches on **ecc and rsa2048 only** and falls through to `rsa2048` for anything
else, `mldsa65` included — so a PQ-APKAM would be verified as RSA and fail. Note that method also reads
`verbParams[atPkamSigningAlgo]`, i.e. the *client-supplied* algo, not the stored record; making it
record-authoritative is SS-3's, and both server changes need parity across every atServer
implementation in the same sweep.
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

### SS-3 — substrate hardening + `signingAlgo` verify · at_secondary_server, at_client · M — [#2086](https://github.com/atsign-foundation/at_client_sdk/issues/2086) — **LANDED on `gkc-pq-d1-spike`** (client) **/ PR [at_server#2736](https://github.com/atsign-foundation/at_server/pull/2736)** (server)

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
**Deliverables → [design.md](design.md)** (SecretStore durability + single-key verify): the enrollment record keeps a **single** `apkamPublicKey`; PKAM verify selects RSA vs
ML-DSA from the record's **`signingAlgo`** (**record-authoritative** — `_validateSignature` reads the
*stored* algo, **not** the client-supplied `verbParams[atPkamSigningAlgo]`; legacy null → `rsa2048`). Plus
the genuine hardening: wire `SecretStorePersistence` to an on-disk per-enrollment backend (preserve monotonic
`putIfNewer` ordering) + jitter/backoff on the anti-storm rate cap.
**Acceptance → [acceptance.md](acceptance.md):** store survives close/reopen with version ordering; an
rsa2048-stamped key verifies via RSA, an mldsa65-stamped key via ML-DSA only (no fallthrough), legacy null →
rsa2048; both functional + e2e.
**Effort:** L.
**Watch-outs:** the `signingAlgo` field on `EnrollDataStoreValue` is owned by SS-1b; the pkam grammar literal
by SS-1a.
**coversD1:** D1-F DEP3 (single-key + signingAlgo).

### SS-4 — nskey minting + signing-root lifecycle + correspondence check · at_client · L — [#2087](https://github.com/atsign-foundation/at_client_sdk/issues/2087) — **ABOUT HALF LANDED on `gkc-pq-d1-spike`**

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
  and `enrollment_chain_link_e2e_test` watches a link survive a real `_apsk` round trip;
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
**Deliverables → [design.md](design.md)** (nskey minting + pqpublickey lifecycle): mint **one** nskey
keypair per `(atSign, namespace)` and publish its public half **eagerly at mint** to
`public:__nskey.<ns>@alice`, taking the short-ttl immutable `_nskeylock.<ns>@alice` first so two of the
owner's enrollments cannot race; the record is **mutable** so B-2 can overwrite it on rotation. Both the
`nskey` public half and
`public:pqpublickey@alice` are **advertised as APKAM-signed envelopes** (design.md §2.1 *Advertised-key
authenticity*), so a fetching client verifies them against the publishing enrollment's `_apsk` — same path
same-atSign and cross-atSign. `pqpublickey` create/seed/serve/pull under
`pqid:<kid>` + root no-namespace serve exception; public/private correspondence check in `_consume` (the
signature is primary; correspondence is the secondary check). The
nskey private is conveyed per-APKAM as a Secret over the substrate.
**Acceptance → [acceptance.md](acceptance.md):** UC-A3.2 (2nd APKAM obtains the nskey private, decapsulates
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

### B-1 — at/nskey + at/symmetric/AES/GCM providers, capability marker, negotiation, cold-start · at_client · XL
**Goal:** the value-level data path — the **D1 GA convergence point**.
**Builds on:** #1930 (seam) + P-1 (`pqSeal`) + S-2 (`CryptoContext.keys`) + **SS-4** (nskey key material) + P-3. *The substrate delivers the privates; this delivers the providers.*
⚠️ **The SS-4 prerequisite holds for `B-1c` onward** — `B-1a` needs no nskey material at all, and `B-1b`
proceeds against a test fixture that supplies the nskey private directly (see the chunk table below). B-1
**as a whole still requires SS-4**; the dependency is not dropped, only deferred past the first two chunks.
**Deliverables (plan-altitude headings; full mechanics → [design.md](design.md), D1 nskey data path):**
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
- **B3 capability marker:** per-`(atSign,namespace)`, advertising the **set of provider ids** the
  fleet supports rather than a boolean — a boolean cannot express *which* schemes are readable and so
  cannot survive a second PQ scheme ([decisions.md](decisions.md) section 16). Initially the set holds
  only `legacy`; per-destination selection picks the best id present in every required reader's set;
  `providerId` on stored values **and** notification frames.
- **B4 cold-start:** when the recipient has never used the namespace, so there is no
  `public:__nskey.<ns>@<recipient>`, the write **fails** — the atSign-level key is a signing root and
  cannot receive an encapsulation, so there is no PQ target to fall back to. The refusal names the
  recipient and the namespace, and a pre-flight query answers the same question first; legacy is
  reachable only by explicit opt-in. The recipient's first *use* of the namespace mints and publishes
  its nskey (via SS-4), and the sender's next `ensureCurrent` re-`plookup` picks it up.
  (Seal-and-hold is a per-namespace policy toggle delivered in **R-1**.)

**Spike state (branch `gkc-pq-d1-spike`, 2026-08-04).** The data path is built, and
**both the self-data and the cross-atSign directions work end to end against a live
atServer**. Advertised nskeys and key packages are signed and verified, cold start fails
cleanly with a pre-flight query and an opt-in legacy escape hatch, and nested namespaces
resolve by walking up with `appMetadata.ns` / `ckNs` on the wire — covered multi-segment in
both live suites, which previously used single-segment namespaces only.
`packages/at_client` green at
**825 passing / 39 skipped**, `tests/at_functional_test` at **113**,
`tests/at_end2end_test` at **43** with no skips (all four re-run together
2026-08-04). Also green: `at_auth` 147, `at_chops` 211, `at_commons` 505.

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
`providerId:sharedBy:sharedWith:namespace:key` as AAD, which is the layer-3 equivalent of
the HPKE `info` binding the conveyance already had. It is a value wire-format change,
taken now because nothing written under the old form exists outside the spike.

*Owed, in rough dependency order:*

| Owed | Where it belongs |
|---|---|
| ~~Cold-start fails by design, with an exception, a fallback and a query~~ — **done on the spike branch.** `NamespaceKeyUnavailableException` carries the atSign and namespace and is raised by the *pre-pass*, so nothing is in flight when it fires; `CryptoRuntime.isReadyFor` answers the same question in advance via the `ReportsReadiness` seam; `AtClientPreference.allowLegacyCryptoFallback` (default false) reroutes the write to legacy, per write, so the fallback is forward-only. Covered live in `nskey_data_path_e2e_test`'s cold-start group ([decisions.md 18](decisions.md#18-pqpublickey-becomes-the-user-owned-signing-root-2026-08-03)) | **B-1c** |
| ~~Advertised-key signature verification~~ — **done on the spike branch, both halves.** `PublishedNskeyKeyRing` signs its own nskey advertisement and `ApkamSignedAdvertisedKeys` verifies a peer's; `KeyPackageRegistration.signedKeyPackagePayload` signs the key package and `VerbEnrollmentDirectory` verifies it against the advertising enrollment's `_apsk`, rejecting unsigned, tampered, wrong-signer and forged-claim packages. No unverified advertised-key path is left. **Owed:** the key-package half has no live coverage — `enroll:listns` is unit-only until SS-2 wires the production path | **SS-1c** / **SS-2** |
| **Client start got two new side effects with `collectConveyedKeyMaterial`, both deliberate and neither yet measured.** Every client carrying an `AtKeysIo` now (a) calls `KeyPackageRegistration.register()` at start, which **publishes `_apsk`** — redundant for an enrollment, since the atServer publishes it on approval, but the only route for a legacy PKAM client whose peers must verify its envelopes; and (b) does one **remote sweep**. That is one extra write and one extra scan per client start, on an unawaited path. The sweep also **consumes and deletes** the envelopes it finds, so an app subscribing to `receivedSecrets` *after* constructing its client sees no arrival event for anything waiting at start — the secret is in the store, which is where `waitForSecret` looks first, so the pull flow is unaffected but a listener-only app is not. Owed: decide whether the `_apsk` publish should be skipped when the client has an enrollment id, and measure the start-up cost | `at_client` |
| ~~The acceptance burn-down misreports progress~~ — **repaired 2026-08-04.** Both audited causes are fixed and the figures are now verified rather than estimated. (a) A row proven in another package can be claimed: `provenIn` cites the live test and asserts it is still there — it does not re-run the proof, since this suite runs in `at_client`'s unit tests and cannot reach the functional or e2e packages, but a renamed or deleted live test now turns the citing row red instead of letting its evidence vanish. (b) `blockers.dart` no longer names landed projects: SS-2, SS-4 and B-1's **21** rows were re-labelled from `blocked: <project>` to `owed: scenario not yet written`, because a project landing makes its scenarios *owed a test*, not *proven* — conflating those is what made the number misleading in both directions. Four had a live proof and now cite it (A2.1, A3.3, A4.1, A4.4), so the suite read **5 of 40** scenario rows green, up from **1**, with **17** genuinely owed a test. The old "4 of 43" was itself wrong optimistically: it counted `catalogue_test.dart`'s three guards as scenarios. The guard that tracked B-1's share now tracks the owed count, since a guard pinned to a finished project silently stops guarding. **Eleven of the 17 were written the same day**, taking the suite to **16 of 40** green and **6** owed: four cross-cutting invariants, UC-A3.4, UC-B5.2, then — once a functional test for the immutable signing-root create existed — the create-once invariant and UC-B5.3's race, and finally UC-A3.2 once its catalogue text was corrected. Then UC-A2.2 and UC-A2.3. Four new live files: `pq_signing_root_create_once_test.dart`, `nskey_seeding_live_test.dart`, `enrollment_namespace_gate_test.dart`, `copied_keyfile_test.dart`. Functional suite **120 green**. UC-A2.3 is proven at two layers deliberately — the row insists the namespace boundary is enforced *at the atServer*, "not by a client-side refusal alone", and a filter in the sender is worth nothing against an enrollment that simply asks for the record; the atServer refuses the scoped enrollment's `llookup` naming the enrollment and the key, while the approver reads the same record, so the refusal is a gate rather than an absent record. What remains owed is **6**: the no-RSA unit row (which enumerates the auth path, so it waits on the ML-DSA row), ML-DSA record-authoritative auth, the atServer half of advertised-key verification, UC-B5.1's offline pull, and the two e2e rows UC-A4.2/UC-A4.3. Two of the six needed no new test: the published nskey's fetchable-not-enumerable property was already proven with controls by `underscore_public_key_hiding_test`, and citing it beat duplicating it. One needed a doc first — the B-1 bench harness had been run when it was built but its numbers were never recorded, so "performance is measured, not assumed" was asking for a budget that existed nowhere a reader could find it ([decisions 28](decisions.md#28-the-pq-performance-budget-measured-2026-08-04)). And one, UC-A3.2, turned out to be a **catalogue error rather than a missing test**: it triggered minting on the first put, which was never built and contradicted UC-A3.3's proven "a keyless write fails". Ruled that the code is right — a put that minted would hide a lock, a keygen, a publish and a per-enrollment conveyance behind one write, on a user action's latency path — and `acceptance.md` 4.2 was amended ([decisions 29](decisions.md#29-uc-a32-describes-a-mint-trigger-that-was-never-built-2026-08-04)). Seeding had unit coverage only, and an `unawaited` call behind a default-false flag is the exact shape that passes every unit assertion while never executing |
| ~~UC-A2.1 is not met, though SS-2 reads complete~~ — **built 2026-08-04**, [decisions.md 23](decisions.md#23-uc-a21-reversing-the-enrollment-key-exchange-2026-08-04). `EnrollmentKeyExchangeMode.pq` stops the enrollee generating and RSA-wrapping `apkamSymmetricKey`; the approver mints it and seals it to the advertised key package over the substrate, and `enrollmentApkamSymmetricKeyResolver` collects it after PKAM. Nothing RSA-wrapped rides the request. Covered live in `enrollment_pq_key_exchange_e2e_test.dart`, including the enrollee recovering the key over its own namespace-scoped PKAM connection. **Owed:** the test cannot pass against `vip` until the atServer relaxation is promoted | **SS-2** residual |
| **The functional rails are pointed away from CI's image and must be reverted before any PR.** `tests/at_functional_test/test/docker-compose.yaml` uses a locally built `at_virtual_env:local` and `runLocal.sh`'s `docker compose pull` is disabled — **uncommitted, deliberate**. The published `virtualenv:vip` does **not** store `EnrollParams.metadata`, so the key-package path cannot be tested against it at all. Before opening a client PR: confirm vip has been promoted, revert both files, and re-run the pack against it | `at_functional_test` |
| **A PQ-capable client cannot tell a legacy atServer from an old peer.** Against an atServer that drops `EnrollParams.metadata`, the key package vanishes silently and the approver reads absence — which [decisions.md 20](decisions.md#20-ss-2-how-the-key-package-reaches-an-enrollment-and-how-conveyance-fires-2026-08-03) ruling 2 treats as *ordinary*, because it also means "an older client". So conveyance no-ops fleet-wide with nothing saying why. UC-B0.1 requires aborting cleanly and logging the reason; `info` returns only a version string, with no feature list to check | **RF-SRV** / UC-B0.1 |
| **Parity across every atServer implementation for the `mldsa65` verify branch.** At least one rejects `signingAlgo:mldsa65` while *parsing* the command, so a PQ client meets an invalid-syntax error rather than an authentication failure. It already stores `signingAlgo` but never reads it, and carries no ML-DSA support — a dependency decision, not an edit | **SS-3** |
| **D1 GA critical path, re-derived 2026-08-04 against pub.dev and the skip counts.** Complete: P-*, S-1/S-2, SS-1a/1b/1c, **SS-2**, **SS-3**, **SS-4** (bar key transparency, parked), **B-1** incl. all chunks. Remaining on the GA path: **R-1** (L, migration machinery + `disallowLegacyEncryption` + strict mode), **B-2** (L, nskey rotation + revocation), **ON-1** (M, PQ-native greenfield onboarding), **R-2** (M, the 4.0.0 flag flip), and **S-3** (L, updatable `.atKeys`/keychain). Off the GA path: the **RF-\*** retrofit trio. Referenced only: D2-1. Separate track: IS-1. Publish gates verified against pub.dev the same day — at_client 3.14.1/3.14.0, at_commons 5.14.0/5.13.0, at_chops 3.4.2/3.4.1, at_auth 3.4.0/3.3.0 (so the old at_auth `3.3.0-rc1`→stable gate is **closed**) | plan |
| **`at_auth` 3.4.0 is open and unpublished**, and at_client now depends on `AtEnrollmentRequest.metadataBuilder`. Same masking as the at_commons row below: workspace resolution hides it, so a green build says nothing | `at_auth` |
| ~~`at_end2end_test` has not been run since at_auth's surface changed~~ — **run 2026-08-04, green at 41 with no skips**, the same count as 2026-08-03. So neither at_auth's added surface (`EnrollmentKeyExchangeMode`, `apkamSymmetricKeyResolver`, `approvedWithMintedKey`, the grown `AtEnrollmentResponse`/`EnrollmentRequestDecision`) nor the arrival-path work regressed it — the latter mattering because that commit added work to `AtClientImpl`'s init, which every e2e test drives. All four rails now verified together: `at_client` 825/39 skipped, functional 113, e2e 43, `at_client_flutter` analyze clean | `at_end2end_test` |
| ~~`NskeyPrivateFiling.start` is an arrival hook nothing calls~~ — **fixed 2026-08-04, and it was three defects rather than one.** The prescription recorded here — give the nskey path `PqSigningRoot.filePendingPrivate`'s store-check treatment — would have produced a second method that looks right and files nothing, because the model it was told to copy had the same defect one layer down. `SecretStore` is an in-memory map whose only populator is `PairwiseSecretSharing.sweepOnce`, and **no production code in `at_client` ever called `sweepOnce` or `startListening`** — so at client start that store is empty and the root private was never filed either. One layer lower again: `KeyPackageRegistration.register()` mints a fresh X-Wing keypair per process (`loadApkamKeys` was wired only in tests), so the running client's `kpid` was never the one its enrollment advertised and a sweep would have scanned an address nobody writes to. `collectConveyedKeyMaterial` closes all three in order — bind the key package to `AtKeys`, sweep remote, then file — and `NskeyPrivateFiling.filePending` replaces `start`/`stop`. Live-covered in `conveyed_key_collection_test.dart`, with both defects reinstated as negative controls: disabling the binding fails the kpid assertion, disabling the sweep fails both tests | `at_client` |
| **The substrate's unit fixture cannot see routing** — one map backs local storage and the atServer, so a local-first write and a remote-first one are indistinguishable by results. Routing is asserted directly instead (`putOptions`, `scanRoutedRemote`). Closing it properly means modelling sync in the fixture | `at_client` tests |
| **`at_client` cannot publish until `at_commons` 5.14.0 does.** Its floor was raised to `^5.14.0` in the same commit as the first use of `Metadata.copy()`, and 5.14.0 is open but unpublished — workspace resolution masks this exactly as the publish-ordering caution warns, so a green build says nothing. `at_chops` 3.4.2 is in the same state, though nothing pins it yet | `at_commons` / `at_chops` |
| ~~The secret-sharing substrate has no live coverage in either pack~~ — **opened, not closed.** `secret_sharing_delivery_test.dart` now drives it live: the envelope is on the atServer by the time `sendEnvelope` returns, and a client that has never synced fetches and decrypts it from there. Both fail against the pre-fix build and nothing else does, so they detect the defect rather than merely passing. **Still owed:** everything beyond envelope delivery — `pushSecretToNamespaceMembers`, the `requestSecret`/`waitForSecret` pull flow, and anything needing two real enrollments, which waits on SS-2 | `at_functional_test` |
| **The substrate's unit fixture backs local storage and the atServer with one map**, so it cannot see a local-first-vs-remote-first defect on the read side at all — which is how the `__ssenv` wake-up ordering bug survived. Fixed for the write side by asserting the put's routing directly and for the sweep by asserting the scan's, but the blind spot itself remains: any future substrate read that depends on routing is untested unless someone remembers to assert the routing rather than the result. Closing it properly means modelling sync in the fixture, so local and remote diverge and a wrong route fails on its results. The live pack now covers the two paths that matter today | `at_client` tests |
| ~~Real nskey minting + per-APKAM conveyance~~ — **done.** `mintAndPublish` takes a remote-first immutable `_nskeylock`, files the private into `AtKeys` **before** publishing, and publishes nothing at all if it cannot. `NskeySeeding` mints at client init across a client's authorised namespaces and conveys every held generation, reading from `AtKeys` rather than the in-memory store. `InMemoryNskeyKeyRing` remains for tests only | **SS-4** |
| ~~**Mint** of `public:pq_signing_root@<atSign>`~~ — **done, and so is its conveyance.** `PqSigningRoot` mints immutable create-once with the private filed before publish; the private is conveyed to fully privileged enrollments at approval under a per-enrollment name, filed into `AtKeys` at start, and `PqSigningChain.publishOwnRootLink` anchors the holder to it at mint and at every start. Live-covered end to end, including that the atServer really does grant `*` + `__manage` — without which the privilege gate would have been tested against two identical cases | **SS-4** |
| ~~Wire the nskey `CryptoConfig` at init~~ — **done 2026-08-04** ([decisions.md 27](decisions.md#27-the-era-default-read-the-new-scheme-everywhere-write-it-once-2026-08-04)). Not by adopting `CryptoConfig.nskey`, which sets the AES-GCM path as the *write* default and is therefore the 4.x shape: final 3.x reads PQ and still writes legacy, so `CryptoConfig.readsNskeyWritesLegacy` registers the same provider set with `defaultProviderId` left at `legacy`. `forClient` stopped being a constant — the providers hold per-atSign state, so the set is built once per client at init and looked up, via an `Expando` rather than written into the shared preference object. The era ring gets the client's `AtKeys` as its `privateFiling`, without which it would see only what this process minted. Live-covered end to end by `era_default_read_test.dart`: **bob, given no `CryptoConfig` at all**, opens a record alice sealed to his namespace key, with alice opting in to `CryptoConfig.nskey` to write PQ — the asymmetry as an executable statement. (An owed item claiming the era ring was unreachable from a test was recorded and then withdrawn the same day: `NskeyProvider.keyRing` is public and exported, so it always was.) | **SS-4** |
| ~~`AtClientPreference.crypto` becomes nullable~~ — **done.** It is `CryptoConfig?`, null meaning "whatever this release encrypts with", and every reader goes through `CryptoConfig.forClient(atClient)` — the one place the era default lives. The SDK deliberately does *not* resolve into the app's preference object: harmless while the default is a const, a per-atSign leak the moment it is not. What SS-4 still owes is the *other* half — building the key ring at init once the default becomes the nskey path | **SS-4** |
| ~~The `_nskeylock` mint/rotate race~~ — **done.** `NskeyMintLock` takes it remote-first, because the atomicity is the atServer refusing a second immutable create; a local-first put would let both enrollments believe they won and collide only at sync. The loser re-reads and adopts rather than waiting | **SS-4** |
| ~~The bench harness `acceptance.md` says lands with B-1~~ — **built 2026-08-04**, `packages/at_client/benchmark/crypto_bench.dart`. Reports three **separately-based** groups and refuses to combine them: *per record* (what every put/get pays once a CK exists — AES-256-GCM vs the legacy AES-256-CTR path), *per (owner, namespace) conveyance* (where PQ actually costs something — X-Wing `pqSeal`/`pqOpen` vs RSA-2048 wrap, paid **once** and then covering every record in scope), and *per authentication* (the ML-DSA-65 ↔ RSA-2048 signature swap). Mixing them is what would produce a headline "PQ is N% slower" from incomparable denominators. **The desktop baseline is now recorded** in [decisions 28](decisions.md#28-the-pq-performance-budget-measured-2026-08-04) — the harness had been run when it was built, but its numbers were never written down, so the acceptance row was asking for a budget that existed nowhere a reader could find it. Headline: at the 256 B size that dominates real traffic, GCM costs **3 µs** more than CTR; the ML-DSA sign a client pays per authentication is **2.7 ms**. **The ceiling is still NOT pinned:** `acceptance.md` requires one reference *low-end* device and the recorded run is a 16-core arm64 Mac, which is the opposite. Nothing here is a regression gate — one desktop run is a baseline, not a threshold | **B-1** |
| ~~`at_chops` `pqOpen` lets an `ArgumentError` escape~~ — **fixed in at_chops 3.4.2** (unpublished): a wrong-length secret key or KEM ciphertext now arrives as `PqOpenException(malformedEnvelope)`. `NskeyProvider`'s client-side guard stays until at_client's floor rises past 3.4.1 | `at_chops` |
| ~~The CK cache and the owner's own nskey privates are process memory only~~ — **half of this was wrong.** Content keys are a genuine cache: the read path re-fetches the `__ck` conveyance record and re-opens it, so a restart costs a round trip, not data. The nskey private is the real exposure, and [decisions.md 21](decisions.md#21-ss-3-where-key-material-lives-and-what-the-substrate-stops-storing-2026-08-03) ruling 1 files it into `AtKeys` on arrival. **Owed:** implement that filing, plus the current-`ckKid` pointer (ruling 2) so a restart stops minting a fresh CK per destination | **SS-3** / **SS-4** |
| ~~`B-1e` does not work~~ — **found and fixed 2026-08-04** ([decisions.md 26](decisions.md#26-uc-a44-a-conveyance-that-loses-the-race-to-its-own-announcement-2026-08-04)). The two-client harness exposed it on its first run: the content-key conveyance was written local-first, so it reached the recipient's atServer only via sync — 31 seconds later in the captured reproduction — while the notification went out immediately over the monitor. The receive path raised `ContentKeyUnavailableException` correctly and the dispatch loop swallowed it at `finer`, dropping the notification silently with no retry. Both notify entry points now route the conveyance remote-first (the same rule as the `__ssenv` ordering fix), and the dispatch `catch` logs at `warning`. **UC-A3.4 / UC-A4.4 are met**, live-covered in `concurrent_notify_test.dart`. Still open, recorded in 26.3: a notification whose transform throws is gone, with nothing re-delivering it when the missing piece lands |
| An enrollment authorised for one namespace must be unable to **decrypt** another's nskey data, not merely unable to fetch it. Not testable yet and deliberately not written: nskey privates are per-ring in-memory until the substrate conveys them, so a second enrollment cannot decapsulate anything at all — the crypto half of the assertion would pass vacuously while the test read as covering it | **SS-4** |
| ~~The notify **receive** half has no live coverage~~ — **closed 2026-08-04.** It did need harness work rather than a test, and the lever was `AtClientManager`'s public constructor: one manager per atSign, each owning its own client, `notificationService` and `syncService`, with `AtClientImpl`'s cache keyed by atSign so two *different* atSigns never collide. `ConcurrentClients` (`lib/src/concurrent_clients.dart`) plus `concurrent_notify_test.dart` now show a monitor on bob receiving and **decrypting** what alice sent, live — the existing `notify_test.dart` had worked around the limitation by switching atSigns and polling `notifyList`, which reads the atServer's queue and exercises neither the monitor nor decryption. Negative control run: reinstating the singleton fails with `@alice stopped=true` from `open`'s own guard. **The constraint to respect:** while a `ConcurrentClients` is open, nothing may call `getInstance().setCurrentAtSign` for either atSign — the cached `AtClientImpl` would be handed a fresh `notificationService`, and the symptom is a subscription that never fires, which reads as a product defect | `at_end2end_test` |
| ~~Rename the atSign-level key in code, delete the `root-pqpublickey` variant~~ — **done.** `NskeyRecipientKind` has one member; no Dart source says `pqpublickey`; the cold-start throw now states why there is no PQ target rather than promising a fallback | **B-1c** |
| ~~Enrollment approval reverses direction~~ — **done.** It needed the atServer after all, though far less of it than "multi-repo seam" implied: the *return* leg rides the existing substrate with no verb change, but the atServer made `encryptedAPKAMSymmetricKey` mandatory on `enroll:request`, so an enrollee that wraps nothing could not send a valid request. That check now yields to an advertised key package and stays mandatory otherwise | **SS-2** |
| `_apsk`'s published value becomes a root-signed envelope rather than a bare key, carried in the enrollment record the atServer already copies. Verifiers accept a bare key as unsigned during transition | **SS-1c** |
| ~~Open an in-progress version in `at_chops` and `at_commons`~~ — **done.** at_chops **3.4.2** and at_commons **5.14.0** are open and unpublished; fold further entries under those headings | `at_chops` / `at_commons` |
| ~~`_addMetadataToBuilder` is a hand-rolled copier~~ — **done.** `Metadata.copy()` (at_commons 5.14.0) is the canonical converter; the notify path copies wholesale and then clears the few fields a sender must not assert, so a field added upstream travels by default. at_client's floor is `^5.14.0` | `at_commons` |

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

**Where the B3 capability marker lands.** `providerId` on stored values comes with `B-1a`/`B-1b`;
per-destination scheme selection with `B-1d` (the first chunk with a non-self destination); `providerId` on
the notification frame with `B-1e`. The marker's own publish/not-ready/flip lifecycle is **R-1** (C1), not a
B-1 chunk.

**Acceptance → [acceptance.md](acceptance.md):** self + shared round-trips byte-exact for text and binary;
UC-A3.1, UC-A3.3 (self cold-start fails, distinctly), UC-A4.1/A4.2/A4.3; B3 mixed-fleet (nskey only when readers'
marker ready, else legacy); UC-A3.4 / UC-A4.4 (providerId travels on the notification frame). Each chunk
carries the scenarios listed against it in the chunk table.
**Effort:** XL — the one project above the ~1–3 PR norm, hence the five-chunk breakdown (~M each).
**Watch-outs:** `recipientKind` has exactly one member, `nskey`, used for self and inbound alike — one key
both ways, so there is no self-vs-inbound variant, and the atSign-level signing root is not a member because
nothing is ever encapsulated to it; no bare `nskey` providerId. The record owner (`sharedBy`, which the
HPKE `info` binds) and the nskey owner (`sharedWith ?? sharedBy`, which selects the key and scopes the CK
cache) are **different atSigns** on any inbound record — conflating them is why cross-atSign reads fail
([decisions.md](decisions.md) section 15). Sweep
`expectAsync`/listener counts for the new notification-frame shape. The CK-conveyed-once rationale
(decision (a)) and the recipientKind enumeration are in [design.md](design.md).
**coversD1:** D1-B B1–B4.

---

## 7. Phase RF — existing-client retrofit (RF-1, RF-SRV, RF-2b, RF-2c)

Off the D1-GA critical path; required for retrofitting existing clients. The substrate facts (pull/push
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
**Deliverables → [design.md](design.md)** (requestSecret pull primitive): confirm generic by-name request →
serve flow + revocation-serve via the `answerSecretRequests` policy / server gate (not an
`excludeEnrollmentIds` param on the serve path — it has none).
**Acceptance → [acceptance.md](acceptance.md):** generic by-name round-trip + revocation-serve.
**Effort:** S.
**Watch-outs:** the selfEncryptionKey-wrap shortcut is rejected (not PQ-safe); CK rotation does not use this.

### RF-SRV — atServer: authenticated self-retrofit enroll (auto-approve + namespace-subset + expiry copy/cap) · at_secondary_server, at_server_spec · L
**Goal:** the server half the retrofit depends on.
**Builds on:** the existing authenticated-request + CRAM auto-approve templates.
**Deliverables → [design.md](design.md)** (authenticated self-retrofit flow): on an `enroll:request`
arriving on an **APKAM-authenticated** connection (`authType==apkam`, resolvable approved enrollmentId; not
CRAM, not legacy PKAM) with a new enrollmentId and **no OTP**, the server (1) validates the requested
namespaces are a **subset** of the authenticating enrollment's (reject escalation); (2) **auto-approves**
(model on the CRAM branch's state=approved / skipCommit-pubkey / set-enrollmentId mechanics **without** its
`__manage`+`*`:rw grant); (3) **copies** the authenticating enrollment's expiry (or null=never) to the new
enrollment; (4) **caps** the old enrollment's expiry to `min(now + serverConfig grace, old's existing
expiry)` **without removing it**; (5) stores/returns `EnrollParams.metadata` (per SS-1a/b). New
`at_secondary_config` grace-duration knob (alongside `enrollmentExpiryInHours`).
**Acceptance → [acceptance.md](acceptance.md):** authed `enroll:request` (new id, no OTP) → auto-approved (no
pending notification), key package stored; escalating namespaces → `UnAuthorized`; the new enrollment
inherits the old's expiry; the old enrollment's ttl is capped (record still present, still authenticates
until the cap elapses); both suites.
**Effort:** L.
**Watch-outs:** net-new is the `apkam`-authType auto-approve branch (NOT the CRAM `*`:rw grant), the
requester-keyed subset check at request time, the expiry copy + old-enrollment ttl cap, and the config knob.
**coversD1:** D1-F retrofit (server); legacy retirement via expiry + revoke.

### RF-2b — at_client: mint PQ (ML-DSA) APKAM + key package, then authenticated auto-approved self-retrofit `enroll:request` · at_client, tests · L
**Goal:** the client half — mint a PQ APKAM and retrofit via a fresh auto-approved enrollment.
**Builds on:** RF-SRV, SS-3, SS-4, P-2.
**Deliverables → [design.md](design.md)** (PQ-APKAM mint + self-retrofit): the client (authenticated with
its pre-PQ keypair) mints — once per keyfile under a host-local lock — an ML-DSA signing keypair + X-Wing
enc keypair, builds the key package, and submits `enroll:request` with a **new enrollmentId** on the
authenticated connection carrying the package as `EnrollParams.metadata` + `signingAlgo=mldsa65` (no OTP).
On the auto-approved response it writes `.atKeys` under the new enrollmentId. Each cloned pre-PQ keyfile
retrofits independently to its **own distinct enrollmentId** (one key package per enrollment, 1:1:1).
**Acceptance → [acceptance.md](acceptance.md):** mint at most once per keyfile (lock under concurrency); a
self-retrofit auto-approves (no human, no OTP, no conveyance) and the client immediately PKAM-auths with the
ML-DSA key under the new id; two clones of one pre-PQ keyfile reach **distinct** enrollmentIds; requested
namespaces ⊆ the authenticating enrollment's.
**Effort:** L.
**coversD1:** D1-F (PQ-APKAM via fresh auto-approved enrollment).

### RF-2c — at_client: retrofit orchestration (old enrollment ages out) + readiness flip + full e2e · at_client, tests · L
**Goal:** the orchestration + readiness flip + end-to-end retrofit, with the old enrollment ageing out.
**Builds on:** RF-2b, RF-SRV, SS-4, SS-2.
**Deliverables → [design.md](design.md)** (retrofit orchestration): authenticate with the pre-PQ keypair →
RF-2b self-retrofit → switch the client to the new enrollmentId's `.atKeys`. The old enrollment **ages out**
via the RF-SRV expiry cap (or an explicit `enroll:revoke`); keep the legacy **encryption** key for reads.
PQ-readiness flip after the new enrollment authenticates. One key package per enrollment (1:1:1).
**Acceptance → [acceptance.md](acceptance.md):** (e2e `@ce2e*`) readiness flips only after the new ML-DSA
enrollment authenticates; previously shared secrets stay openable; the old enrollment stops authenticating
once its capped expiry elapses (or after `enroll:revoke`) — **not** via an in-place key delete;
seal-once-reaches-every-host; revoke/expire-one-host; sync-less wake-up.
**Effort:** L.
**coversD1:** D1-F end-to-end (retrofit via fresh enrollment).

---

## 8. Phase R/B — rollout, rotation, retirement & versioning (R-1, B-2, B-3, ON-1, R-2)

**Stated once:** at_auth 4.0 (S-5) is a **different major at a different time** from at_client 4.0 (R-2).
The forward-secrecy/rotation levers and the `disallowLegacyEncryption` flag semantics live in
[design.md](design.md); the high-level 3.x-off / 4.x-on trajectory is in [roadmap.md](roadmap.md); the
rotation-policy ruling is in [decisions.md](decisions.md).

### R-1 — migration machinery + `disallowLegacyEncryption` flag (default false) + strict-mode · at_client · L
**Goal:** the readiness lifecycle, scheme-negotiation default, and the PQ-write flag.
**Builds on:** B-1.
**Deliverables → [design.md](design.md)** (migration machinery + flag semantics): **C1** readiness-marker
lifecycle (publish not-ready on upgrade; flip ready when the fleet is upgraded — **operator-declared
primary**; auto-detect optional); **C2** behaviour-neutral default (rebuild reads all, keeps writing legacy
until the flag flips); **C3** strict-mode toggles incl. cold-start seal-and-hold; **D1-D** the
`disallowLegacyEncryption` flag on `AtClientPreference` — final at construction (immutable), **default
false**, SHOUT at creation when false, governs only legacy-provider *encryption* (legacy read +
`shouldEncrypt=false` unaffected); cold-start PQ fallback (`at/nskey` to root) must **not** trip the refusal.
Additive within 3.x.
**Acceptance → [acceptance.md](acceptance.md):** negotiation matrix (write only what every reader supports,
else legacy, else refuse when flag true); flag=true → every write `providerId ∈ {at/nskey,
at/symmetric/AES/GCM}`, legacy-only recipient → refused, legacy read still works, flag immutable;
UC-B3.x/B4.x/B5.2 at the scheme-selection layer with a seeded marker/nskey state (full e2e of B3.x/B4.x
defers to RF-2c).
**Effort:** L.
**Watch-outs:** the readiness flip is the only operator judgement call (warn on a recent legacy check-in).
Operator-declared readiness is the primary signal; auto-detect is optional. Don't bump the version pre-publish
(fold under the in-progress at_client heading).
**coversD1:** D1-C + D1-D D1/D2 / WP7.

### B-2 — nskey rotation + revocation (CK rotation = coarse FS, nskey-keypair rotation = PCS) · at_client · L
**Goal:** the two rotation levers + revocation composition — the **D1 GA** rotation slice.
**Builds on:** B-1 + R-1 + **(RF-1 + SS-3)** for the per-enrollment substrate fan-out (1:1:1). ⚠️ **depends
on RF-1+SS-3, NOT the full RF-2** (Open decision #C) — so **D1 GA does not wait on the auth retrofit**.
**Deliverables → [design.md](design.md)** (rotation/revocation levers): **B5a** CK rotation (O(1), on
ordinary sync, delete old `__ck` + evict; default RETAIN, FS-mode is the delete+evict knob); **B5b**
nskey-keypair rotation (O(n) PCS / per-APKAM revocation: take `_nskeylock.<ns>@<owner>`, mint a new nskey
keypair, **overwrite** `public:__nskey.<ns>@<owner>` with the new `{nskeyKid, publicKey}`, convey the new
private per-APKAM via the substrate excluding revoked, release; old privates retained = history-on, not
per-message FS; a late joiner is pushed the current generation only and pulls older ones on demand via
`requestSecret`, addressable because each `__ck` names its `nskeyKid`); **B6** revocation
composition
(auth-revoke + rotate-exclude + optional history re-encrypt [D2]); inbound cross-atSign FS is **bilateral**
(documented trade-off).
**Acceptance → [acceptance.md](acceptance.md):** UC-A5.1 (both levers); UC-A5.2/A5.3 + B6 (revoked/excluded
enrollment can't read post-rotation; bilateral inbound FS); functional nskey self+shared / rotation /
mixed-scheme / cold-start / revoke+rotate-exclude; e2e at_talk chat scenario. **▶ at_client 3.14.x = D1 GA.**
**Effort:** L.
**Watch-outs:** don't conflate the levers (CK rotation does NOT ride the per-APKAM substrate).
**coversD1:** D1-B B5/B6.

### B-3 — selfEncryptionKey + shared_key.* retirement, phases 1-3 · at_client, **at_secondary_server**, at_auth · L
**Goal:** retire the legacy self-encryption key (a distinct project from B-2's rotation work).
**Builds on:** B-2.
**Deliverables → [design.md](design.md)** (selfEncryptionKey retirement): **Phase 1** stop using
selfEncryptionKey for new writes (default → nskey path); **phase 2** lazy re-encrypt on touch (+ optional
background sweep, per-atSign progress observable); **phase 3** stop conveying it — ⚠️ needs an **at_server
change**: `enroll:approve` currently *mandates* `encryptedDefaultSelfEncryptionKey`; relax to optional,
sequenced **after** phase 2. (Phase 4 stop-existing is **R-2**.)
**Acceptance → [acceptance.md](acceptance.md):** a touched legacy value lazily re-encrypts (providerId
legacy → at/symmetric/AES/GCM); migration progress query; a post-migration `enroll:approve` omits the self
key and the enrollee onboards without it.
**Effort:** L.
**coversD1:** D1-B B7 phases 1-3.

### ON-1 — PQ-native greenfield onboarding + legacy-interop flag · at_client, at_client_flutter · M  *(critic gap — UC-A1.1)*
**Goal:** a brand-new atSign onboards PQ-native (the root of Part-A coverage).
**Builds on:** RF-2b (PQ-APKAM mint) + SS-4 (pqpublickey) + R-1 (readiness).
**Deliverables → [design.md](design.md)** (PQ-native onboarding): at CRAM onboarding mint a **PQ (ML-DSA)
APKAM** keypair (no RSA APKAM required for auth); immutable-create `public:pqpublickey@<atSign>`; no
`selfEncryptionKey` minted (self data uses the nskey path); readiness can be **ready** (no legacy APKAM
exists); a **legacy-interop config flag** (default off → PQ-only, no RSA `public:publickey`) that, when
enabled, publishes the RSA pubkey for legacy-peer inbound.
**Acceptance → [acceptance.md](acceptance.md):** UC-A1.1 (PQ-native onboard: APKAM=pq, pqpublickey
immutable, readiness ready, KP registered); UC-B4.2 (legacy peer ↔ PQ atSign resolves only via the flag);
default PQ-only onboarding has no RSA pubkey.
**Effort:** M.
**coversD1:** Catalogue Part-A root + Decision #1 / UC-B4.2.

### R-2 — at_client 4.0.0: flip `disallowLegacyEncryption` default to true + selfEncryptionKey stop-existing · at_client · M
**Goal:** PQ-safe on every write path by default (the final cutover).
**Builds on:** R-1 + B-2 + RF-2c + S-6. **Gated on the ecosystem floor** (last published downstream versions).
**Deliverables → [design.md](design.md)** (the v4 flip + B7 phase 4): flip the default to **true** (SHOUT if
re-enabled false); **B7 phase 4** — onboarding no longer generates `selfEncryptionKey`, drop it from the
AtKeys model; general dead-code removal (deprecated methods; the `package:encrypt` files deleted-not-migrated).
The legacy provider itself **stays** (reads forever).
**Acceptance → [acceptance.md](acceptance.md):** flag-true → every write PQ, legacy-only recipient refused,
legacy read still works (UC-B5.2); new atSign has no selfEncryptionKey; full unit/functional/e2e green.
**▶ at_client 4.0.0.**
**Effort:** M.
**Watch-outs:** different major / different time from at_auth 4.0 (S-5). Don't remove the legacy provider.
**coversD1:** D1-D D3 + D1-B B7 phase 4.

---

## 9. Phase D2 — referenced only (D2-1, out of D1 GA)

### D2-1 — carve `at/pqmls` provider + D1-E shape fixes · at_client · L
**Goal:** carve the v1 `at/pqmls` group provider and apply the D1-E shape fixes.
**Builds on:** **#1930** (the M0 seam — *not* B-1; the provider uses only seam types) + **SS-2** (the
per-APKAM substrate the group reuses). Off the D1 critical path; **must not gate D1 GA.**
**Deliverables → [design.md](design.md)** (at/pqmls structural shape carried forward): carve the v1
`at/pqmls` group provider keyed onto the per-APKAM substrate (via `EnrollmentDirectory.listForNamespace` +
`KeyPackage`); apply D1-E fixes — lift membership into `SecureGroup`, binary-safe, rename
`PairwiseGroup`→`SelfGroup` (scope the grep to `PairwiseGroup`, not `Pairwise`); pin the provider wire id
to `at/pqmls`.
**Acceptance → [acceptance.md](acceptance.md):** round-trips via the seam (text + binary byte-exact);
per-APKAM re-key (rotate distributes epoch keys to each enrollment's KeyPackages); rename sweep clean.
**Effort:** L.
**coversD1:** **D1-E only** (the provider itself is D2).
**Watch-outs:** D2 work; the v1 epoch engine is thrown away at the MLS swap — invest only in the
carried-forward interface shape. **D2 proper (pq-mls engine, Group Delivery Service, identity hardening) is
out of scope here** — see [roadmap.md](roadmap.md) for the D2 trajectory.

---

## 10. Cross-cutting: publish gates, critical path, waves/parallelism, testing

### (a) Publish gates
- `at_chops` (P-1, P-2) and `at_commons` (SS-1a) publish **before** `at_server`/consumers bump pins.
- `at_auth` is split **additive-3.3.0** (S-1; 3.2.0 was consumed by the network-timeout release) then **breaking-4.0.0** (S-5) so the `AtKeys`/`AtKeysIo`
  extend-in-place bakes before the barrel cut.
- `at_client` stays **minor 3.14.x** through D1 GA; the v4 flip (R-2) is the final gated cutover.

**Package versions & release sequencing** (single reference — publish in dependency order; two majors —
`at_auth` 4.0 (S-5, WASM split) and `at_client` 4.0 (R-2, the flag flip) — at different times):

| #  | Package             | Bump                          | Project(s) | Why |
|----|---------------------|-------------------------------|------------|-----|
| 1  | `at_chops`          | minor `3.2.1 → 3.3.0` **(published 2026-06-23, done)** | P-1    | stateless functional core + HPKE `pqSeal`/`pqOpen`; `@Deprecated AtChopsImpl` shim |
| 2  | `at_chops`          | minor `3.3.0 → 3.4.0` **(published 2026-07-17, done)** | P-2 | #2030 (`at_chops_ffi` barrel + `AtPqc` + `AtSignatureAlgorithm`) landed the 3.4.0 bump on trunk 2026-07-03 (+ #2046); P-2's `mldsa65` verify branch (#2056, 07-06) and #2039 (AES-GCM FFI, 07-09) folded into the same slot, which then published. Minor under the one-time semver exemption ([decisions.md](decisions.md) 2026-07-03) |
| 3  | `at_commons`        | minor `5.11.0 → 5.12.0` **(published 2026-07-04, done)** | SS-1a | `EnrollParams.metadata` + `signingAlgo`; flattened `listns`; pkam `mldsa65` literal. *(at_commons has since published 5.13.0, 2026-07-17, outside this program.)* |
| 4  | `at_auth`           | minor `3.2.0 → 3.3.0` **(3.3.0-rc1 published 2026-07-17; stable pending)** | S-1 | additive: extend `AtKeys` in place (deprecate legacy); `AtKeysIo` runtime persistence; `InMemoryAtKeysIo`. ⚠️ **the rc1 → stable promotion is an open gate** — S-6 and SS-2's at_auth work need a stable 3.3.0 to pin against; timing unresolved |
| 5  | `at_auth`           | **major `3.3.0 → 4.0.0`**     | S-5        | breaking WASM cut: `FileAtKeysIo` → `at_auth_io.dart`; default removed; registrar → `package:http` |
| 6  | `at_client`         | minor `3.14.x → 3.15.x`       | S-2…B-2    | `at_auth ^4.0.0`; `CryptoContext.keys`; nskey data path; rotation. **= D1 GA**. ⚠️ **3.13.0 and 3.14.0 both published 2026-07-17** (3.14.0 carries the SS-0 substrate as an experimental surface), so the GA slot has moved off 3.14.x — re-derive the target minor at execution against pub.dev. ⚠️ **S-2's `CryptoContext.keys` (#2076) is on trunk but unreleased** — it merged after 3.14.0 published, so the next at_client release is the first that carries it |
| 7  | `at_client`         | **major `3.15.x → 4.0.0`**    | R-2        | flip `disallowLegacyEncryption` default → true; selfEncryptionKey stop-existing; dead-code removal |
| 8  | `at_onboarding_cli` | minor `1.16.0 → 1.17.0`       | S-6        | `at_auth ^4.0.0`; imports `FileAtKeysIo` from `at_auth_io.dart`; explicit injection. 1.16.0 published 2026-07-17, so 1.17.0 is a clean next slot |
| 9  | `at_client_flutter` | minor `1.1.4 → 1.2.0`         | S-6        | `at_auth ^4.0.0`; `file_picker` imports `at_auth_io.dart` |
| 10 | `at_cli_commons`    | minor (constraint bump)       | S-6        | consumes the new `at_onboarding_cli` / `at_client` (transitive at_auth) |

**Dependency-floor bumps (at_client's own pins).** at_client's constraints on trunk are `at_chops ^3.0.0`
and `at_commons ^5.9.0`; both floors rise during D1:

| at_client pin | Floor bump          | Lands at | Why |
|---------------|---------------------|----------|-----|
| `at_chops`    | `^3.0.0 → ^3.3.0`   | SS-0     | the substrate baseline needs the published `pqSeal`/`pqOpen` (3.3.0) — landed with #2037 |
| `at_commons`  | `^5.9.0 → ^5.12.0`  | SS-1c    | the flat `listns` grammar + `EnrollParams.metadata` (5.12.0) |

⚠️ Workspace resolution wires `at_chops`/`at_commons` as path deps, so a too-low floor still resolves green
locally **and** in CI — these floor bumps must be made **explicitly**, not inferred from a passing workspace
build.

### (b) Critical path to D1 GA
`#1930(done) → P-1 + S-2 → SS-1a → SS-1b → SS-1c → SS-2 → SS-3 → SS-4 (+ P-3) → B-1 → R-1 → B-2`
(D1 GA: rebuild = universal reader, one flag = PQ writer, opt-in rotation).
**Branch state (2026-08-04):** `gkc-pq-d1-spike` is **68 commits ahead of `origin/trunk` and 2 behind**;
both of those two are docs-only (the wasm-port plan, [#2118](https://github.com/atsign-foundation/at_client_sdk/pull/2118)),
so the drift carries no code-merge risk today.

**Everything up to and including SS-3 is landed as of 2026-08-03** (SS-1c/SS-2/SS-3 on `gkc-pq-d1-spike`, plus [at_server#2736](https://github.com/atsign-foundation/at_server/pull/2736) for SS-3's server half). **`SS-4`'s signing chain landed 2026-08-04** — mint, root-private conveyance, self-anchoring and the graded walk, all live-covered. What remains of SS-4 is the nskey `CryptoConfig` wiring at init and key-transparency publication, so **`B-1` is what the path now waits on**, and it gates the final 3.x release.
**Off-path (parallel):** `RF-SRV → RF-2b → RF-2c` (RF-1 confirm), `B-3`, `ON-1`, `S-5 → S-6`, `D2-1`, `KF-1`
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
per-UC harness and given/when/then live in [acceptance.md](acceptance.md).

### (e) Conformance
Every PQ-touching PR — in **at_client_sdk** OR any **atServer implementation** — must cite a **project id**
from this plan (`P-1`, `P-2`, `P-3`, `S-*`, `SS-*`, `KF-1`, `B-*`, `R-*`, `RF-*`, `ON-1`, `D2-1`) **or** a
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
| D1-A (PQ primitives, enrollment key) | P-1, P-2, P-3 |
| D1-B B1-B4 (data path) | B-1, chunks B-1a…B-1e (+ key material SS-4) |
| D1-B B5/B6 (rotation/revocation) | B-2 |
| D1-B B7 (selfEncryptionKey retirement) | B-3 (phases 1-3), R-2 (phase 4) |
| D1-C / D1-D (migration, flag, versioning) | R-1, R-2 |
| D1-F substrate baseline | SS-0 (PR #2037) |
| D1-F DEP1-DEP4 | SS-1b, SS-2, SS-3 |
| D1-F retrofit | RF-SRV, RF-2b, RF-2c (RF-1 confirm) — retirement via expiry + revoke (1:1:1; no per-key-delete project) |
| D1-E (at/pqmls shape) | D2-1 (D2) |
| UC-A1.1 PQ-native onboard + Decision #1 / UC-B4.2 | ON-1 |
| UC-A2.x / A3.x / A4.x / A5.x | SS-4, B-1, B-2, RF-2b |
| UC-B0.x..B5.x | RF-2c (retrofit) + R-1 (scheme negotiation) |

See [acceptance.md](acceptance.md) for the full UC catalogue; [decisions.md](decisions.md) records the D1-F
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
- **#E** — S-2 scope / the §3-S5-vs-§7-WP3 SoT conflict: this plan takes additive-field-only.
- **#F** — enrollment cardinality + retrofit shape: **RESOLVED 2026-06-30** — **1:1:1** + fresh-enrollment
  retrofit. (Drives SS-3 single-key, RF-SRV, and RF-2b/c.)

**Verification.** This plan is verified against the live trees: the `at_client_sdk` monorepo — which
**contains** `at_chops`, `at_auth`, and `at_commons` as workspace packages (`packages/at_chops`,
`packages/at_auth`, `packages/at_commons`) — plus the separate atServer implementation repos.

---

## 13. Phase IS — inter-server PQ authentication (IS-1)

*Off the D1 GA critical path (server-to-server, `at_server`), but in D1 scope (ruled 2026-07-06). This is
the atServer↔atServer handshake, orthogonal to the client-side `nskey` data path (§6) — a compromised
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
#1889. Design detail in [design.md](design.md) (§8 inter-server PQ authentication).

**Watch-outs:** `pq_signing_publickey` is looked up live every handshake and never cached — keep it that
way, so a re-published key takes effect on the next handshake with no rotation machinery. Do not
re-introduce a KEM, cert, or tag: the UUID challenge the swapped signature covers is the entire freshness
mechanism, and the TLS session already secures the channel.

