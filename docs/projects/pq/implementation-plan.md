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
  - **Track B — key management:** `at_auth` (`WritableAtKeys`, `AtKeysIo` widening, the WASM barrel
    split) → the PQ enrollment-conveyance key.
  - **Track C — at_client crypto seam + migration:** `crypto.dart` / `crypto_runtime.dart` / `legacy/`,
    `AtClientPreference`; the publish ladder.
  - **Track D — storage + platform + consumers:** `LocalKeystoreAtKeysIo`, the updatable `.atKeys`
    file path, `at_onboarding_cli` / `at_client_flutter` / `at_cli_commons`.
  Within `at_client/crypto/`, the file partition keeps A and C apart: **C** owns `crypto.dart`,
  `crypto_runtime.dart`, `legacy/`; **A** owns `crypto/group/`, `crypto/nskey/` (new), `secret_sharing/`.
  The nskey providers are mostly new files — low collision by construction.
- **Land contracts first.** Merge the tiny interface PRs (the `pqSeal` signature, the `WritableAtKeys`
  API, the `CryptoContext.keys` field) first, stubs OK, so every track compiles against stable shapes
  and never blocks on another.
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
  [#1993 done]→  P-1 at_chops 3.3.0 (published)    P-2 mldsa65 verify (publish 3.4.0, indep root)
                     │                                   │
  [#1930 done]→  S-2 CryptoContext.keys (additive)       │
                 S-1 at_auth WritableAtKeys ─→ S-3 LocalKeystore/.atKeys updatable
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
     R-2 at_client 4.0 (flip flag default true) — final, gated on the ecosystem floor
```

**Hosted-publish ordering (stated once).** `at_chops` (`P-1`, `P-2`) and `at_commons` (`SS-1a`) are
**hosted** → publish before `at_server`/consumers bump pins. `at_commons`, `at_chops`, and `at_auth` all
live in this monorepo as workspace packages (`packages/at_commons`, `packages/at_chops`, `packages/at_auth`);
only `at_server` / `java_at_server` are separate repos. ⚠️ **Caution:** workspace resolution wires these as
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

### P-2 — at_chops: wire `mldsa65` into the verification branch; publish a NEW minor · at_chops · M (≈1 PR)
**Goal:** the one missing ML-DSA verification branch (the enum member + algo classes already ship in 3.3.0).
**Builds on:** — (independent root; parallel to P-1). ⚠️ The `_getVerificationAlgorithm` `mldsa65` branch
**did NOT make the 3.3.0 publish** — trunk `at_chops` has no ML-DSA verify branch, so P-2 needs **its own
at_chops minor** (**3.4.0 or later**), it cannot fold into the already-shipped P-1 3.3.0.
**Deliverables → [design.md](design.md)** (at_chops primitives, ML-DSA): add an `mldsa65` branch in
`_getVerificationAlgorithm` returning `MlDsa65PureDartAlgo()` (no `DynamicLibrary` in `AtChopsImpl` — do
**not** claim FFI-when-available); no new `SigningAlgoType` member, no new algo class; publish in the new
minor. **Coordinate the slot:** two FFI PRs are **also** claiming a 3.4.0 slot — #2030 (the `at_chops_ffi`
barrel + `PqcFfi` auto-resolver) and #2039 (AES-GCM FFI) — so sequence P-2 against them into **one agreed
3.4.0** (agreed contents), not a free slot each. Those FFI PRs realise the **FFI-auto-resolve-default** policy
(FFI when available, pure-Dart fallback, WASM forces pure-Dart — ruling in [decisions.md](decisions.md)); they
are **in D1 scope**, on the at_chops track.
**Acceptance → [acceptance.md](acceptance.md):** **algorithm-level** sign/verify (true) + tamper (false);
rsa/ecc/pkam unchanged. Do **not** assert end-to-end `AtChops.verify(mldsa65)` — the deprecated sync path
doesn't await the async ML-DSA verify.
**Effort:** M.
**Watch-outs:** publish the 3.4.0 minor before `at_server` bumps its pin in SS-3; agree the 3.4.0 contents
with PR #2030/#2039 first. **ML-DSA APKAM auth is retained** — the
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
**nothing to deprecate**; (2) `WritableAtKeys` **subclasses** at_auth's `AtKeys` (the material holder); (3)
`CryptoRuntime` resolves against the live `AtClientPreference.crypto`, and cached-client reuse adopts the
new config (there is no `CryptoRegistry`).

**Parallelism fact (stated once)** — `S-1`/`S-2`/`S-3` do **not** gate Wave-2 substrate work; the substrate's
`P-1`/`pqSeal` publish gate is **already satisfied** (at_chops 3.3.0, published 2026-06-23), leaving the SS-0
baseline (PR #2037) as its prerequisite (see [section 10](#10-cross-cutting-publish-gates-critical-path-wavesparallelism-testing)).

### S-1 — at_auth: `WritableAtKeys` holder + `WrittenAtKeysIo` widening (API only); publish 3.2.0 · at_auth · M
**Goal:** the single in-memory holder of every key (per-enrollment AND per-APKAM); interface-first.
**Builds on:** at_auth `AtKeys`. Additive only; gates nothing in Wave 2.
**Deliverables → [design.md](design.md)** (structural design: WritableAtKeys/key stores): `WritableAtKeys
extends AtKeys` (add/remove/write); widen `WrittenAtKeysIo` (plain `abstract`, externally *extended* by
`KeychainAtKeysIo`) with add/remove/update + default impls; `InMemoryAtKeysIo`. ⚠️ `AtKeysIo` is `sealed`
— the real break surface is `WrittenAtKeysIo`; concrete-default-on-abstract is the correct mitigation for
its `extends`-users.
**Acceptance → [acceptance.md](acceptance.md):** existing onboard/auth suites green; `WritableAtKeys`
add→read→remove; `InMemoryAtKeysIo` round-trip (persistent round-trip proven once **S-3** wires the stores).
**Effort:** M.
**Watch-outs:** ⚠️ **version** — pub.dev latest at_auth is **3.1.0**, in-tree is **3.1.1** (unshipped).
Publish 3.1.1 first **or** fold `WritableAtKeys` under the unshipped slot before cutting 3.2.0 (Open
decision #D).
**coversD1:** D1-S S2.

### S-2 — at_client: `CryptoContext.keys` additive field (interface-first only) · at_client · S (≈1 PR)
**Goal:** the tiny field the data path compiles against.
**Builds on:** #1930 + S-1's `WritableAtKeys` type.
**Deliverables → [design.md](design.md)** (CryptoProvider seam): add `WritableAtKeys keys` to
`CryptoContext` (additive); `CryptoRuntime` threads it into provider calls.
**Acceptance → [acceptance.md](acceptance.md):** existing crypto/legacy round-trips green; behaviour-neutral
(no wire/stored-value change); Mode-B regression retained.
**Effort:** S.
**Watch-outs:** ⚠️ **Scope cut** — keep ONLY the additive field; **defer** migrating `LegacyCryptoProvider`
to read from `context.keys` (legacy pulls remote `plookup`s + `atChops` cipher ops the 6 static fields
can't supply). This plan keeps `LegacyCryptoProvider` reading its own sources (additive-field-only) — see
Open decision #E in [decisions.md](decisions.md).
Resolve where `context.keys` is sourced at construction (overlaps S-3).
**coversD1:** D1-S S5.

### S-3 — at_client/at_auth: `LocalKeystoreAtKeysIo` + updatable `.atKeys`/keychain · at_client, at_auth, at_client_flutter · L
**Goal:** durable, updatable key-storage homes (bootstrap→file/keychain, distributed/rotating→keystore,
ephemeral→memory). Stores are **dumb** — convergence stays in the substrate.
**Builds on:** S-1's widened update API.
**Deliverables → [design.md](design.md)** (key stores): `LocalKeystoreAtKeysIo` over the 5.x keystore; make
`FileAtKeysIo` updatable (re-wrap the self-encryption key on rewrite, atomic write + backup); compose
`WritableAtKeys` at AtClient construction.
**Acceptance → [acceptance.md](acceptance.md):** post-onboarding key add persists + survives close/reopen;
ephemeral stays in-memory; **migration test** on a v(N-1) `.atKeys`/store fixture (backend is **Hive**
today, not SQLite — keep the test backend-agnostic; name any legacy box/table explicitly); a **keychain
updatable round-trip on mobile/desktop**; functional onboard+add+read-next-run green.
**Effort:** L.
**Watch-outs:** file rewrite must re-wrap the self-enc key or it's unreadable next run; run the integration
suite at every commit boundary (resource lifecycle). Does **not** gate the substrate.
**coversD1:** D1-S S2/S3.

### S-5 — at_auth 4.0.0: WASM barrel split · at_auth · L  *(parallel, off the GA critical path)*
**Goal:** make the at_auth core WASM-safe (the one breaking major in the program).
**Builds on:** S-3 (so `WritableAtKeys` + updatable stores bake on 3.2.0 before the breaking cut).
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
**coversD1:** D1-S keyfile-at-rest + backup/restore (new scope).

**NoPorts uptake (pointer).** NoPorts is the roadmap's finish line, yet this plan carries no NoPorts work
package. NoPorts adoption of the PQ-safe data path is **tracked in the NoPorts repo, out of this plan's
lane** — sequenced after B-1 (a PQ-capable `at_client` reader/writer) is available. If a NoPorts-side WP is
later pulled into this lane, slot it after B-1.

---

## 5. Phase SS — Secret-sharing substrate (SS-1a, SS-1b, SS-1c, SS-2, SS-3, SS-4)

The `SS-*` projects define the secret-sharing substrate work; the substrate design lives in
[design.md](design.md) §2. **SS-0 lands the substrate baseline first** — SS-1c / SS-2 / RF-1 all presuppose
the substrate code from PR #2037, which is not yet on trunk.

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
   public half is **published lazily**: on first use it is the owner-only self at-key `nskey.<ns>@alice`
   (synced to Alice's `<ns>`-authorised clients, **not** a `public:` key); on the namespace's first
   cross-atSign share the **same** public half is promoted to the world-readable `public:nskey.<ns>@alice`
   (immutable create-if-absent). Its private — a KEM private that **decapsulates** CKs, never decrypts
   application data — is conveyed per-APKAM as a Secret over the substrate.
5. **appMetadata carries NO `ns` field** (see B-1 in [section 6](#6-phase-b--the-nskey-data-path-b-1-the-d1-centrepiece)).

### SS-0 — land the WP-SS substrate baseline · at_client · M
**Goal:** get the WP-SS secret-sharing substrate code onto trunk — the foundation SS-1c / SS-2 / RF-1
presuppose but that lives only on the feature branch today.
**Builds on:** #1930 + P-1 (`pqSeal`, published 3.3.0).
**Deliverables → [design.md](design.md)** (secret-sharing substrate): land the WP-SS substrate baseline
(**draft PR #2037**, branch commit `6184eab12`), **reworked to the 1:1:1 / flat `listns` / no-write-path
shape before merge** (single `apkamPublicKey` + `signingAlgo`; flat discovery roster; no
`registerKeyPackage` / `enroll:metadata` write path). This is the `__ssenv` envelope, `SecretStore`,
`putIfNewer` ordering, `kpid` addressing, and the push/pull primitives the later SS projects wire up.
**Acceptance → [acceptance.md](acceptance.md):** substrate unit suite green; the baseline compiles in the
1:1:1 shape with no write-path residue.
**Effort:** M.
**Watch-outs:** PR #2037 must be reworked to the current shape (1:1:1, flat `listns`, no write path) **before**
merge — don't land the pre-decision-#F shape. It is the prerequisite for SS-1c / SS-2 / RF-1; those projects
cite PR #2037 as "already landed," not implied trunk state.
**coversD1:** D1-F substrate baseline.

### SS-1a — at_commons enroll grammar: `EnrollParams.metadata` + flattened `listns`; publish 5.12.0 · at_commons · M
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

### SS-1b — server: store/return `EnrollParams.metadata` + flattened `listns` + first live round-trip · at_secondary_server, at_server_spec · L
**Goal:** persist the opaque blob and serve the gated discovery roster.
**Builds on:** SS-1a (publish first).
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

### SS-1c — wire at_client to the live verbs + flattened parser · at_client, tests · M
**Goal:** drive the live verbs and parse the flat shape.
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

### SS-2 — substrate wired into AtClient + server wake-up; key-package-in-request (new-device conveyance only) · at_secondary_server, at_client, at_auth, at_commons · L
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
**Watch-outs:** ⚠️ the atServer-schema change (separate `at_server`/`java_at_server`) must land in the same
release; ~1KB blob size limit; listener-before-trigger for the wake-up subscription.
**coversD1:** D1-F DEP4 + production wiring (new-device conveyance).

### SS-3 — substrate hardening (durable store + jitter) + single `apkamPublicKey` + `signingAlgo` verify · at_secondary_server, at_client · L
**Goal:** durable secret storage + smoothed anti-storm + the single-key record-authoritative verify.
**Builds on:** SS-2 ◀ P-2.
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

### SS-4 — nskey minting + pqpublickey lifecycle + correspondence check · at_client · L–XL
**Goal:** mint the per-namespace key material and the atSign-level root PQ key — the first convergence
feeder into the data path.
**Builds on:** SS-3 + **P-3** (pqpublickey name/cold-start target) + **S-3** (LocalKeystore for nskey
privates).
**Deliverables → [design.md](design.md)** (nskey minting + pqpublickey lifecycle): mint **one** nskey
keypair per `(atSign, namespace)` and store its public half as the owner-only self at-key
`nskey.<ns>@alice` (this alone suffices for self data — Alice's own clients hold it); publish the
world-readable `public:nskey.<ns>@alice` **lazily**, on the namespace's first cross-atSign share
(immutable create-if-absent, promoting the same public half). Both the `nskey` public half and
`public:pqpublickey@alice` are **advertised as APKAM-signed envelopes** (design.md §2.1 *Advertised-key
authenticity*), so a fetching client verifies them against the publishing enrollment's `_apsk` — same path
same-atSign and cross-atSign. `pqpublickey` create/seed/serve/pull under
`pqid:<kid>` + root no-namespace serve exception; public/private correspondence check in `_consume` (the
signature is primary; correspondence is the secondary check). The
nskey private is conveyed per-APKAM as a Secret over the substrate.
**Acceptance → [acceptance.md](acceptance.md):** UC-A3.2 (2nd APKAM obtains the nskey private, decapsulates
a test secret sealed to it; app_2 refused to an app_1-only client); a fetched `nskey` / `pqpublickey`
advertisement verifies against the publisher's `_apsk` and a tampered one is rejected; UC-B5.1/B5.3 (offline
pull; create-once race); pqpublickey create→seed→serve→pull + correspondence-mismatch rejection.
**Effort:** L–XL.
**Watch-outs:** delivers **key material only** — the value-level providers are B-1. The **first convergence
feeder** into the data path.
**coversD1:** nskey/pqpublickey material slice of D1-B B1 + D1-F F2.

---

## 6. Phase B — the nskey data path (B-1, the D1 centrepiece)

### B-1 — at/nskey + at/symmetric/AES/GCM providers, capability marker, negotiation, cold-start · at_client · XL
**Goal:** the value-level data path — the **D1 GA convergence point**.
**Builds on:** #1930 (seam) + P-1 (`pqSeal`) + S-2 (`CryptoContext.keys`) + **SS-4** (nskey key material +
pqpublickey cold-start target) + P-3. *The substrate delivers the privates; this delivers the providers.*
**Deliverables (plan-altitude headings; full mechanics → [design.md](design.md), D1 nskey data path):**
- **Layer 3 — `at/symmetric/AES/GCM`:** AES-256-GCM under a symmetric CK cited by `ckKid` only;
  `appMetadata{providerId, ckKid, iv}` (**no `ns` field**); binary-safe; CK cache keyed
  `(owner, namespace, ckKid)`.
- **Layer 2 — `at/nskey`:** `pqSeal` the CK to the recipient's nskey public half, written once as
  `<ckKid>.__ck.<ns>@<owner>`; `appMetadata{providerId, recipientKind, ckKid}` (**no `ns` field**). Self
  data seals to the owner's own nskey (its self at-key); sharing seals to the recipient's nskey (fetched
  via `plookup` once published to `public:`) — one keypair, same provider, uniform self/cross flow.
- **Get/put routing:** out-of-order sync (decapsulate `<ckKid>.__ck` on demand with the one nskey
  private — no self-vs-inbound branch — else deferred `Stream.error`); discover a recipient's published
  `public:nskey` via `plookup`, re-fetch on decapsulation-failure/rotation.
- **B3 capability marker:** per-`(atSign,namespace)`, initially not-ready; per-destination scheme
  selection; `providerId` on stored values **and** notification frames.
- **B4 cold-start:** when the recipient's namespace has no published `public:nskey`, seal **only the CK**
  to `public:pqpublickey@<recipient>` (`recipientKind: root-pqpublickey`; data stays AES-GCM under the CK,
  never encapsulated to root); the recipient's first cross-atSign share lazily promotes its nskey public
  half to `public:` (via SS-4), and a later send upgrades to `recipientKind: nskey`. (Seal-and-hold is a
  per-namespace policy toggle delivered in **R-1**.)
**Acceptance → [acceptance.md](acceptance.md):** self + shared round-trips byte-exact for text and binary;
UC-A3.1, UC-A3.3 (self cold-start self-heals), UC-A4.1/A4.2/A4.3; B3 mixed-fleet (nskey only when readers'
marker ready, else legacy); UC-A3.4 / UC-A4.4 (providerId travels on the notification frame).
**Effort:** XL.
**Watch-outs:** `recipientKind` is `nskey` (self + inbound, one key both ways) or `root-pqpublickey`
(cold-start) — there is no self-vs-inbound `recipientKind`; `root-pqpublickey` is still an `at/nskey`
conveyance, **not** a 3rd providerId; no bare `nskey` providerId. The nskey public half starts as the
owner-only self at-key and is promoted to `public:` only on first cross-atSign share. Sweep
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
nskey-keypair rotation (O(n) PCS / per-APKAM revocation: mint a new nskey keypair, re-publish its public
half — re-promoting to `public:` if it was published — and convey the new private per-APKAM via the
substrate, excluding revoked; old privates retained = history-on, not per-message FS); **B6** revocation
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
- `at_auth` is split **additive-3.2.0** (S-1) then **breaking-4.0.0** (S-5) so `WritableAtKeys` bakes before
  the barrel cut.
- `at_client` stays **minor 3.14.x** through D1 GA; the v4 flip (R-2) is the final gated cutover.

**Package versions & release sequencing** (single reference — publish in dependency order; two majors —
`at_auth` 4.0 (S-5, WASM split) and `at_client` 4.0 (R-2, the flag flip) — at different times):

| #  | Package             | Bump                          | Project(s) | Why |
|----|---------------------|-------------------------------|------------|-----|
| 1  | `at_chops`          | minor `3.2.1 → 3.3.0` **(published 2026-06-23, done)** | P-1    | stateless functional core + HPKE `pqSeal`/`pqOpen`; `@Deprecated AtChopsImpl` shim |
| 2  | `at_chops`          | minor `3.3.0 → 3.4.0`         | P-2        | ML-DSA `mldsa65` verify branch; **coordinate the 3.4.0 slot** with PR #2030 (`at_chops_ffi` barrel + `PqcFfi` auto-resolver) + PR #2039 (AES-GCM FFI) — one agreed 3.4.0 |
| 3  | `at_commons`        | minor `5.11.0 → 5.12.0`       | SS-1a      | `EnrollParams.metadata` + `signingAlgo`; flattened `listns`; pkam `mldsa65` literal |
| 4  | `at_auth`           | minor `3.1.1 → 3.2.0`         | S-1        | additive: `WritableAtKeys`; `AtKeysIo`/`WrittenAtKeysIo` widened; `InMemoryAtKeysIo` |
| 5  | `at_auth`           | **major `3.2.0 → 4.0.0`**     | S-5        | breaking WASM cut: `FileAtKeysIo` → `at_auth_io.dart`; default removed; registrar → `package:http` |
| 6  | `at_client`         | minor `3.13.0 → 3.14.0`       | S-2…B-2    | `at_auth ^4.0.0`; `CryptoContext.keys`; nskey data path; rotation. **= D1 GA** ⚠️ pub.dev latest is **3.12.0**, in-tree **3.13.0** (unshipped) — publish the in-progress slot first **or** fold; decide at execution against pub.dev |
| 7  | `at_client`         | **major `3.14.0 → 4.0.0`**    | R-2        | flip `disallowLegacyEncryption` default → true; selfEncryptionKey stop-existing; dead-code removal |
| 8  | `at_onboarding_cli` | minor `1.16.0 → 1.17.0`       | S-6        | `at_auth ^4.0.0`; imports `FileAtKeysIo` from `at_auth_io.dart`; explicit injection ⚠️ pub.dev latest is **1.15.0**, in-tree **1.16.0** (unshipped) — publish or fold; decide at execution against pub.dev |
| 9  | `at_client_flutter` | minor `1.1.3 → 1.2.0`         | S-6        | `at_auth ^4.0.0`; `file_picker` imports `at_auth_io.dart` |
| 10 | `at_cli_commons`    | minor (constraint bump)       | S-6        | consumes the new `at_onboarding_cli` / `at_client` (transitive at_auth) |

**Dependency-floor bumps (at_client's own pins).** at_client's constraints on trunk are `at_chops ^3.0.0`
and `at_commons ^5.9.0`; both floors rise during D1:

| at_client pin | Floor bump          | Lands at | Why |
|---------------|---------------------|----------|-----|
| `at_chops`    | `^3.0.0 → ^3.3.0`   | SS-0     | the substrate baseline needs the published `pqSeal`/`pqOpen` (3.3.0) |
| `at_commons`  | `^5.9.0 → ^5.12.0`  | SS-1c    | the flat `listns` grammar + `EnrollParams.metadata` (5.12.0) |

⚠️ Workspace resolution wires `at_chops`/`at_commons` as path deps, so a too-low floor still resolves green
locally **and** in CI — these floor bumps must be made **explicitly**, not inferred from a passing workspace
build.

### (b) Critical path to D1 GA
`#1930(done) → P-1 + S-2 → SS-1a → SS-1b → SS-1c → SS-2 → SS-3 → SS-4 (+ P-3) → B-1 → R-1 → B-2`
(= at_client 3.14.x, D1 GA: rebuild = universal reader, one flag = PQ writer, opt-in rotation).
**Off-path (parallel):** `RF-SRV → RF-2b → RF-2c` (RF-1 confirm), `B-3`, `ON-1`, `S-5 → S-6`, `D2-1`, `KF-1`
(builds on S-3), and the final `R-2`.

### (c) Waves / parallelism
The wave-1 → wave-2 boundary is **soft** — the "waves" are parallelism groupings, not barriers; the actual
gating is the per-project dependency list. **The substrate has no remaining publish gate** — its only publish
dependency, `P-1`/`pqSeal` on `at_chops` 3.3.0, **shipped to pub.dev 2026-06-23**; `S-1`/`S-2`/`S-3`
(WP2/WP3/WP4) do **not** block Wave 2 either. The substrate's remaining prerequisite is the **SS-0 baseline**
(PR #2037) landing on trunk, not a hosted publish.

| Gate item                        | Blocks the substrate? |
|----------------------------------|-----------------------|
| P-1 (at_chops 3.3.0 / `pqSeal`)  | No — already published (2026-06-23); substrate ungated |
| S-1 (`WritableAtKeys` + `AtKeysIo`) | No |
| S-2 (`CryptoContext.keys`)       | No — sibling of the substrate on the critical path, not a prerequisite |
| S-3 (`LocalKeystoreAtKeysIo`)    | No |

**Merge discipline.** Per-package PRs to **trunk** in dependency order (no mega-PRs); rebase on trunk daily;
keep PRs small + additive / flag-gated so trunk stays releasable; prove cross-package combinations with an
**ephemeral** integration branch (or CI), not a standing one. **Interface-first** — freeze the `pqSeal`
signature (P-1), the `WritableAtKeys` API (S-1), and the `CryptoContext.keys` field (S-2) first (stubs OK).
Integration is **continuous**, not a final step: each project merges to trunk when complete and publishes as
needed.

### (d) Testing harness pointer
`runLocal.sh` with `docker compose down` first, capped 180s; a test that mints `.atKeys` clears its own at
start and gitignores it; run **both** `tests/at_functional_test` and `tests/at_end2end_test` for any server
type/shape change (separate packages, invisible to at_client's own `dart test`/`analyze`). The detailed
per-UC harness and given/when/then live in [acceptance.md](acceptance.md).

### (e) Conformance
Every PQ-touching PR — in **at_client_sdk** OR **at_server** / **java_at_server** — must cite a **project id**
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
| D1-S S2/S3 (WritableAtKeys, stores) | S-1, S-3 |
| D1-S S4 (WASM split) | S-5 |
| D1-S S5 (CryptoContext.keys) | S-2 |
| D1-S S6 (consumer bumps) | S-6 |
| D1-S keyfile-at-rest + backup/restore (new scope) | KF-1 |
| D1-A (PQ primitives, enrollment key) | P-1, P-2, P-3 |
| D1-B B1-B4 (data path) | B-1 (+ key material SS-4) |
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
`packages/at_auth`, `packages/at_commons`) — plus the separate `at_server` / `java_at_server` repos.

