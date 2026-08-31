# acceptance.md — The gates, and what each one actually proves

**Status:** acceptance catalogue (binding). Lives in `docs/projects/wasm/`.
**Purpose:** the tiered gate ladder **T0–T6** for the implementation-neutral
`AtClient` work, the measured evidence behind each tier, and — for every tier — an
explicit statement of what it does *not* establish.
**Status refreshed:** 2026-08-27, against `trunk` at `9d9e5f7d7`. The measured
baseline in §1 is dated where it was taken and is not re-measured on a status pass.
**Lane:** this doc owns *what must be true and how it is checked*. For the seams
themselves see [`design.md`](design.md); for sequencing see
[`implementation-plan.md`](implementation-plan.md); for the rulings see
[`decisions.md`](decisions.md); for the thesis see [`roadmap.md`](roadmap.md); for the
JS/TS boundary that T6 gates see [`js-api.md`](js-api.md).

## Table of contents

- [0. Why this doc is tiered](#0-why-this-doc-is-tiered)
- [1. The measured baseline](#1-the-measured-baseline)
- [2. T0 — structural neutrality](#2-t0--structural-neutrality)
- [3. T1 — compile](#3-t1--compile)
- [4. T2 — execute under Node + dart2wasm](#4-t2--execute-under-node--dart2wasm)
- [5. T3 — execute under Chrome + dart2wasm](#5-t3--execute-under-chrome--dart2wasm)
- [6. T4 — live browser against an atServer](#6-t4--live-browser-against-an-atserver)
- [7. T5 — native non-regression](#7-t5--native-non-regression)
- [8. T6 — the JavaScript boundary](#8-t6--the-javascript-boundary)
- [9. Cross-cutting gates](#9-cross-cutting-gates)
- [10. The honest limit](#10-the-honest-limit)

---

## 0. Why this doc is tiered

The predecessor plan's acceptance section had two compile gates at the top and
treated everything else as follow-up. That ordering encoded a belief that turned out
to be wrong: that the compiler rejects `dart:io`.

It does not. The gate ladder below is ordered by **what each tier can prove**, and
the compile tier is deliberately demoted to third.

| Tier   | Gate                               | Proves                                                       | Blind to                                  |
| ------ | ---------------------------------- | ------------------------------------------------------------ | ----------------------------------------- |
| **T0** | Structural dependency-tree walk    | Platform libraries are absent from the reachable graph       | Logic that is portable but wrong          |
| **T1** | `dart compile wasm`                | `dart:ffi`/`dart:html`/`dart:js`/`dart:mirrors` are absent   | **`dart:io` and `dart:isolate` entirely** |
| **T2** | `dart test -p node -c dart2wasm`   | Pure-Dart logic executes correctly under WasmGC              | Browser APIs; untested code paths         |
| **T3** | `dart test -p chrome -c dart2wasm` | Browser-API-dependent code executes                          | Untested code paths                       |
| **T4** | Live browser vs. atServer          | The whole stack works end to end                             | Everything the scenarios don't touch      |
| **T5** | Native suites                      | No behavioural regression on native                          | —                                         |
| **T6** | The JavaScript boundary            | What crosses to JS is what the TypeScript signature promised | The protocol itself — that is T4          |

T0 and T5 are the **ratchet**: once green they run on every commit. T1–T3 turn on as
the sweep progresses, package by package. T6 turns on with the facade.

---

## 1. The measured baseline

Everything in this section was measured on **Dart SDK 3.12.0 (stable)**, Linux x64,
**2026-08-13**. Re-measure on SDK upgrade; these are toolchain behaviours, not
specification guarantees.

### 1.1 `dart compile wasm` does not reject `dart:io`

Program: a reachable, non-tree-shakeable `File('/tmp/...').existsSync()` plus
`Platform.pathSeparator`, printed so it cannot be eliminated.

```
$ dart compile wasm bin/main.dart -o out.wasm
Generated wasm module 'out.wasm', and JS init file 'out.mjs'.
$ echo $?
0
```

Per-library results, each a one-line `import` plus a trivial `main`:

| Library        | Result                                                                         |
| -------------- | ------------------------------------------------------------------------------ |
| `dart:io`      | **compiles**, exit 0                                                           |
| `dart:isolate` | **compiles**, exit 0                                                           |
| `dart:ffi`     | rejected — `Error: Dart library 'dart:ffi' is not available on this platform.` |
| `dart:html`    | rejected — same form                                                           |
| `dart:js`      | rejected — same form                                                           |
| `dart:mirrors` | rejected — same form                                                           |

### 1.2 The `dart:io` stub throws at runtime

The module from §1.1 was instantiated and invoked under **Node 24.18.0**:

```
Unsupported operation: _Namespace
    at wasm://wasm/b2a98d02:wasm-function[13]:0x2e82
```

So the failure mode is precisely: **compiles clean, throws on first use**. This is
the behaviour the whole project is organised against.

### 1.3 The runtime test gate works today, without a browser

```
$ dart test -p node -c dart2wasm
00:00 +0: [Node.js, Dart2Wasm] loading test/probe_test.dart
Generated wasm module '…/probe_test.dart.node_test.dart.wasm.wasm', and JS init file '…mjs'
00:00 +2: All tests passed!
```

Both probe tests passed, including one asserting
`const bool.fromEnvironment('dart.library.io') == false` — confirming the suite really
ran under the WASM configuration and not on the VM.

### 1.4 The Chrome gate compiles but was not executed here

```
$ dart test -p chrome -c dart2wasm
Generated wasm module '…/probe_test.dart.browser_test.dart.wasm', and JS init file '…mjs'
Failed to load "test/probe_test.dart": Failed to run Chrome: No such file or directory
```

The dart2wasm *compilation* path for the browser platform is confirmed working; the
launch failed only because no Chrome binary exists in this WSL environment. **T3 has
therefore not been observed executing** and must be validated the first time it runs
in CI, where GitHub's `ubuntu-latest` runners ship Chrome.

### 1.5 dart2js is blind to `dart:io` as well — and permits more

The same per-library probes through `dart compile js`:

| Library           | dart2js      | dart2wasm |
| ----------------- | ------------ | --------- |
| `dart:io`         | compiles     | compiles  |
| `dart:isolate`    | compiles     | compiles  |
| `dart:html`       | **compiles** | rejected  |
| `dart:js`         | **compiles** | rejected  |
| `dart:js_interop` | compiles     | compiles  |
| `dart:ffi`        | rejected     | rejected  |
| `dart:mirrors`    | rejected     | rejected  |

dart2js emits the same `_Namespace` throwing stub. **No Dart web compiler gates
`dart:io`** — so [`decisions.md`](decisions.md) D-7's choice of dart2js costs nothing in
safety, and T0 carries the guarantee under either target.

### 1.6 The JS/TS boundary kills the process on an unconverted `Future`

Measured with `@JSExport` + `createJSInteropWrapper` called from Node 24.18.0: a Dart
`Future` returned without `.toJS` crosses as an opaque handle, and when it completes
with an *error* it surfaces as an uncaught exception that **terminated the process** —
no rejection, nothing catchable. Separately, dart2js on Node leaves **every Promise
permanently pending** unless `globalThis.self = globalThis` is set before load, with no
error raised.

Both are silent failures, which is why T6 gates them explicitly. Full tables in
[`js-api.md`](js-api.md) §1.

---

## 2. T0 — structural neutrality

**The primary gate.** Because T1 is blind to `dart:io` (§1.1), a dependency-tree walk
is the only mechanism that can establish neutrality.

### T0.1 — no platform library in the reachable graph

Walk every `import`/`export` reachable from each neutral barrel, across package
boundaries and into third-party packages, resolving configurable URIs **the way a web
build does** (`dart.library.io` false, `dart.library.js_interop` true). Fail on any
file naming `dart:io`, `dart:ffi`, `dart:isolate`, `dart:html`, `dart:js` or
`dart:mirrors`.

Barrels in scope: `package:at_client/at_client.dart`,
`package:at_lookup/at_lookup.dart`, `package:at_utils/at_utils.dart`,
`package:at_chops/at_chops.dart`, and `package:at_auth/at_auth.dart` via the PQ
program's S-5 — [`roadmap.md`](roadmap.md) §5.

**Gated as of 2026-08-27: `at_chops` and `at_auth`. Nothing else.** The gated set is
declared in `.github/wasm_gates.yaml` and nowhere else. `at_utils`, `at_lookup` and
`at_client` own 3, 6 and 7 offenders respectively and are deliberately absent, so that a
declared gate asserts a package is web-safe rather than recording how far it has to go.
Each joins as its phase lands — at_lookup with Phase 2, at_utils and at_client with
Phase 4.

**`dart:html` and `dart:js` are policy here, not toolchain.** Under
[`decisions.md`](decisions.md) D-7 the JS/TS artifact is built with dart2js, which
**accepts both** (§1.5). They stay on the forbidden list so that a dart2wasm build
remains possible at zero cost — which means this gate is the only thing enforcing them.
Removing them from the walk silently forecloses dart2wasm.

**Done when:** the walk reports zero offenders in package-owned sources, and the set
of externally-blocked packages is empty.

**Implementation: shipped.** `tools/wasm_shakedown` — a standalone CLI, not a test —
run in CI by the `wasm_shakedown` and `wasm_ratchet` jobs of
`.github/workflows/at_libraries.yaml`, as a hard gate rather than allowed-to-fail. It
walks the graph across package boundaries via `.dart_tool/package_config.json`,
resolving configurable URIs the way the target platform would. A stanza carries three
keys, and the third is the one worth knowing about:

| Key        | Asserts                                                             |
| ---------- | ------------------------------------------------------------------- |
| `ratchets` | nothing forbidden is reachable from a barrel (T0.1, T0.2)           |
| `probe`    | the barrel compiles — the libraries dart2wasm rejects outright (T1) |
| `controls` | the ratchet above has not quietly stopped proving anything          |

`controls` are mandatory, and the parser rejects a stanza without one. Every ratchet
check is about what the walk did *not* find, so a walk that found nothing satisfies all
of them; a control walks the other side of the platform seam and asserts the walk still
*reaches* something known to be there. Without one, `at_chops_ffi.dart` could be emptied
and the gate would still read green. `min_files_walked` guards the same failure from the
other direction. See `tools/wasm_shakedown/README.md`.

### T0.2 — the ratchet

**Shipped one-way, not two-way as originally specified.** Each ratchet names the sources
allowed to reach a forbidden library (`allowed_offenders`) plus a ceiling on how many
packages anywhere in the graph own one (`max_blocked_packages`). A source outside the
allow list, or a count above the ceiling, fails. Fixing a source or dropping a
dependency **passes with no edit here** — the baseline just goes loose, and the printed
figures say so: `6/7 offenders` means one listed file no longer reaches anything.

Why the change. A two-way ratchet demands an edit to this repo's gate config in the same
commit as every fix, including fixes made for unrelated reasons in other packages, and it
fails the build for good news. One-way keeps the only mandatory edit a *tightening*, done
when convenient. The cost is that a stale-loose baseline no longer self-reports as a
failure, which the printed figures mitigate: every run prints them whether or not it
fails.

There is deliberately no way to write a baseline back from a run. A generator existed and
was removed — the failure output already prints the full live walk.

### T0.3 — conditionals must have both branches walked

**Restated. The original ban is withdrawn.** This gate read: no file under a neutral
package's `lib/` contains `if (dart.library.`, turnable on immediately because the tree
had zero. `at_auth` 4.0.0-rc1 then shipped exactly one, deliberately and with a recorded
rationale — `lib/src/auth/probe_default.dart` exports `probe_default_web.dart`, or
`probe_default_io.dart` under `dart.library.io`. Both branches are real implementations;
neither is a stub. A ban would have had to allow-list the one construct it exists to
forbid on the day it was written. See [`decisions.md`](decisions.md) D-1 and OQ-1.

What is enforced instead: **a conditional in a gated package must have both of its
branches walked.** The ratchet resolves web-side, which covers one branch. A `control`
resolves with io semantics by default, so pointing one at the same barrel covers the
other — and `environment: web` on a control pins the web branch where that is the half
in question. Absent the second walk, the ratchet passes just as convincingly when the
conditional was skipped and neither branch was seen. at_auth's stanza carries exactly
this control, on the file axis rather than the library axis, because `at_auth.dart` under
io resolution reaches `dart:io` through half a dozen files and `reaches_library` would
prove nothing there.

The construct stays discouraged by D-1 — this makes it *auditable* where it survives, not
approved as a default.

### T0.4 — no throwing fallbacks

No neutral-package source throws `UnsupportedError` (or equivalent) from a
platform-capability fallback. Enforces D-2. A capability that a platform lacks must be
unreachable there, not reachable-and-explosive.

**Watch-out:** this is a grep-shaped gate and will catch legitimate uses (e.g. an
`AtKeysIo` subtype refusing `write`). Maintain an explicit allow-list with a reason per
entry rather than loosening the pattern.

**Not implemented.** `wasm_shakedown` has no throwing-stub key; its three are `ratchets`,
`probe` and `controls`. D-2 is therefore upheld by review, not by CI. The reachability
gate covers the shape that actually bit us — a capability that is *absent* on web — while a
hand-written stub is reachable-and-explosive and passes T0.1 cleanly. Worth landing before
Phase 4, where the sweep removes the native defaults that stubs are the tempting
substitute for.

### What T0 does not prove

That the code is *correct* under WasmGC. A package can be perfectly neutral and still
mis-handle a 64-bit integer, a `String` encoding, or an async ordering difference. That
is what T2 exists for.

---

## 3. T1 — compile

**Necessary, not sufficient. Deliberately third.**

| ID   | Gate                                                                                                                                               | Done when |
| ---- | -------------------------------------------------------------------------------------------------------------------------------------------------- | --------- |
| T1.1 | A program importing `package:at_client/at_client.dart` and constructing nothing compiles under **both** `dart compile js` and `dart compile wasm`. | Exit 0.   |
| T1.2 | A program that builds an `AtClient`, onboards from in-memory `.atKeys` material, and calls `put`/`get`/`delete`/`getKeys` compiles under both.     | Exit 0.   |

Both compilers are run because [`decisions.md`](decisions.md) D-7 ships the dart2js
artifact while keeping dart2wasm open; the second is what keeps it open.

**What T1 proves**, and it is narrow:

| Compiler    | Catches                                            | Blind to                                          |
| ----------- | -------------------------------------------------- | ------------------------------------------------- |
| dart2wasm   | `dart:ffi`, `dart:html`, `dart:js`, `dart:mirrors` | `dart:io`, `dart:isolate`                         |
| **dart2js** | `dart:ffi`, `dart:mirrors` — **that is all**       | `dart:io`, `dart:isolate`, `dart:html`, `dart:js` |

For this codebase the dart2wasm run amounts to exactly one thing — the at_chops OpenSSL
island stays quarantined behind `at_chops_ffi.dart`.

**What T1 does not prove:** anything at all about `dart:io` or `dart:isolate` (§1.1,
§1.5). Do not cite a green T1 as evidence of readiness. Whenever T1 appears in a PR
description or a status update, T0's result must appear beside it.

---

## 4. T2 — execute under Node + dart2wasm

**The gate the predecessor doc lacked entirely**, and the one that converts "compiles"
into "runs". Available locally with no browser infrastructure (§1.3) — but, as of
2026-08-27, **not in CI**, deliberately.

**Why it is not wired up.** On the hosted `ubuntu-latest` runner every suite fails to load
before any test body executes: the CJS bootstrap calls `instantiate` from the ESM `.mjs`
init file and gets `undefined`. The same command passes locally on Dart 3.12 + Node 24,
and neither is pinned in the workflow, so a CI failure here would report a toolchain
mismatch and not a fact about our code. It waits for a pinned pair where a failure means
something. Recorded here rather than as a silent omission, and it is the reason
[`implementation-plan.md`](implementation-plan.md) R5 is withdrawn rather than done.

Two mechanics worth carrying into that work, measured while getting the suites to run
locally: `dart2wasm` emits one module per test file, so `--concurrency=1` is the wrong
knob to reach for, and `Uri.base` throws under dart2wasm on Node.

| ID   | Gate                                                                                                                                                                                                               | Done when       |
| ---- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | --------------- |
| T2.1 | `dart test -p node -c dart2wasm` green in `at_utils`.                                                                                                                                                              | All tests pass. |
| T2.2 | Same in `at_lookup` (protocol/verb-builder/response-parser tests; socket tests excluded as `_io`).                                                                                                                 | All tests pass. |
| T2.3 | Same in `at_chops` — the pure-Dart barrel only, `--exclude-tags ffi`. Executes `cryptography`, `pqcrypto` and `better_cryptography` rather than merely building them, closing open questions C1–C3 by measurement. | All tests pass. |
| T2.4 | Same in `at_client` for every suite not requiring local storage or a socket.                                                                                                                                       | All tests pass. |

**Cost note.** T2 is close to free *once the toolchain pair is pinned*: the suites
already exist and the runner does the compilation. The integration is a matrix dimension
in `.github/workflows/at_libraries.yaml` plus pinned Dart and Node versions — the second
half is what is missing, not the first.

### What T2 does not prove

Only the paths the tests touch. Record a coverage figure over the T2 run and hold a
floor; where coverage is thin, T0 is what carries the guarantee, because absence from
the graph does not depend on being exercised. State both numbers together in the
project status rather than the coverage figure alone.

---

## 5. T3 — execute under Chrome + dart2wasm

For everything T2 cannot reach: IndexedDB, the SQLite-wasm VFS, `WebSocket`,
`navigator.onLine`, and any `package:web` interop.

| ID   | Gate                                                                                                                                             | Done when       |
| ---- | ------------------------------------------------------------------------------------------------------------------------------------------------ | --------------- |
| T3.1 | `dart test -p chrome -c dart2wasm` green for the `at_client_web` storage backend, including a write/reload/read cycle against the IndexedDB VFS. | All tests pass. |
| T3.2 | Same for the `at_client_web` transport, against a stub WebSocket endpoint.                                                                       | All tests pass. |
| T3.3 | The whole T2 set re-run under Chrome, confirming no dart2js-vs-Chrome-WasmGC divergence.                                                         | All tests pass. |

**Prerequisite:** the first CI run must confirm the platform executes at all — it was
not observed locally (§1.4).

---

## 6. T4 — live browser against an atServer

Carried over from the predecessor doc's gates B1–B6; they were well chosen.

| ID   | Gate                                                                                                                                         | Done when                                                                                      |
| ---- | -------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------- |
| T4.1 | A page loads the WASM module, opens `wss://<host>:<port>/ws` against a virtualenv atServer, and receives the `'@'` prompt.                   | Prompt observed; `from` / `pkam` complete.                                                     |
| T4.2 | The same page performs `update` then `lookup` for a self key.                                                                                | Value matches.                                                                                 |
| T4.3 | Write a key, reload the page, read it back from local storage with the network untouched (`remoteLocalPref` unset).                          | Value survives the reload.                                                                     |
| T4.4 | A key written by a native client for the same atSign appears in the browser client's local storage via the normal sync path, and vice versa. | Both directions observed. Exercises `AtSyncQueue` on its backend-neutral store.                |
| T4.5 | The browser client shares a key with a second atSign; a native client for that atSign decrypts it.                                           | Plaintext matches. Confirms the pure-Dart crypto path is *correct*, not merely running.        |
| T4.6 | `.atKeys` content pasted into the page decrypts (Argon2id in pure Dart) and yields a working `AtClient`.                                     | Session authenticates. **Record the wall-clock decryption time** — it is the phase-6 UX input. |

---

## 7. T5 — native non-regression

| ID   | Gate                                                                                                                                       | Done when                                                                                                                                                 |
| ---- | ------------------------------------------------------------------------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------- |
| T5.1 | `dart analyze --fatal-warnings` and `dart test --concurrency=1` green in every package touched by a seam change, at every commit boundary. | Zero new failures.                                                                                                                                        |
| T5.2 | `tests/at_functional_test` and `tests/at_end2end_test` `runLocal.sh` both green, with `docker compose down` before each run.               | Both green. **Required** for any change to connection or storage lifecycle — the `AtConnection` change is a wire-path change, and unit-green is not done. |
| T5.3 | `at_onboarding_cli` and `at_client_flutter` compile and pass against the new majors with explicit injection.                               | Both green. Coordinate with the PQ program's S-6, which bumps the same consumers.                                                                         |

---

## 8. T6 — the JavaScript boundary

Gates the facade described in [`js-api.md`](js-api.md). Run against the **dart2js**
artifact ([`decisions.md`](decisions.md) D-7), and against the dart2wasm build too for as
long as that target is kept open.

Both of this tier's headline failures are **silent** (§1.6), so every assertion must be
timeout-bounded. A bare `await` in a T6 test does not fail on the defect it is meant to
catch — it hangs the suite, which reads as an infrastructure flake.

| ID   | Gate                                                                                                                                                       | Done when                                                                                                    |
| ---- | ---------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------ |
| T6.1 | The compiled artifact loads under Node and in a browser, and the facade object is reachable with the expected method names.                                | Object present; method set matches the `.d.ts`.                                                              |
| T6.2 | **Every** exported async method settles within a fixed timeout — resolve or reject, never pending.                                                         | All settle. Catches the dart2js/Node scheduler trap and any missed `.toJS`.                                  |
| T6.3 | **No unconverted `Future`, `Stream`, `List`, `Uint8List`, `CItem`, `CEvent` or `Predicate` escapes the facade.** Static check over `lib/src/js/`: every exported member returns a JS type. | Zero violations. This is the process-killer (§1.6) — a static gate, not a runtime one. Extended 2026-08-18 for the collections types added by `decisions.md` D-10/D-11. |
| T6.4 | Every thrown Dart exception arrives as a catchable `AtError` with a stable `code`, never as the default boxed rejection. **Includes `CollectionOpException`/`OpFailure`** — a batch partial-failure must arrive as the same `AtError` shape, not a second result-union type ([`js-api.md`](js-api.md) §6). | Mapped for every exception class the facade can raise, `CollectionOpException` included; the generic message appears nowhere. |
| T6.5 | `subscribe`-shaped APIs deliver events and stop delivering after unsubscribe. **Includes all eight `AtCollection` stream-returning members.** | Events observed, then none after cancel. |
| T6.6 | A TypeScript-supplied `KeyStore` satisfies the Dart interface and round-trips a value.                                                                     | Round-trip succeeds. This is the Node storage path ([`js-api.md`](js-api.md) §7).                            |
| T6.7 | The published `.d.ts` type-checks against a sample TS consumer that exercises the whole surface.                                                           | `tsc --noEmit` clean. The typings are hand-written with no drift detection — this is the only check on them. |
| T6.8 | **An unknown `CEvent` subtype reaches the JS consumer as a generic `'unknown'` event, not dropped and not thrown.** `CEvent` is deliberately not `sealed` upstream (`collections.dart:5077`) — a future minor can add a subtype the encoder does not yet know. | A synthetic unrecognised subtype (test-only) round-trips to a discriminated-union member the sample TS consumer's default branch handles. New 2026-08-18, `decisions.md` §2.6 F8. |
| T6.9 | **A record written by the JS facade carries its declared `typeTag` on the wire**, not `'n/a'`. Regression guard for `decisions.md` §2.6 F3/D-11 — the write-compatibility gap the whole collections design has to solve for. | The stored envelope's `type` field equals the tag declared at `collection()` call time, once J1a's route (upstream `writeTypeTag` or the carrier-class shim) ships. Until then this gate is expected-red and must be tracked as such, never skipped. New 2026-08-18. |

### What T6 does not prove

That the *protocol* works — T4 covers that. T6 proves only that the boundary is faithful:
what crosses is what the TypeScript signature promised.

---

## 9. Cross-cutting gates

| ID  | Gate                                                                                                                                                                                                                    | Done when                                                                                              |
| --- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------ |
| X1  | **Persistence conversion integrity.** The hive→sqlite→hive round-trip gate stays green, and `bin/compare_persistence.dart` reports identical for a native-SQLite vs web-SQLite database written from the same workload. | Exit 0 from both. Proves the web open path produces the same on-disk schema, not merely a working one. |
| X2  | **Payload budget.** Measure and record the shipped byte total — compiled `.wasm` + `sqlite3.wasm` + JS glue, gzipped and Brotli.                                                                                        | A recorded number, taken **before** the SQLite-vs-IndexedDB decision, not after.                       |
| X3  | **Argon2id timing.** Measured under T3 and again under T4.6.                                                                                                                                                            | A recorded number; drives the deferred UX work.                                                        |

---

## 9a. Gates added 2026-08-30

These follow from D-12..D-18. Three of them close holes where the existing ladder measured
**speed** on a concern named for **correctness** or **confidentiality**.

### 9a.1 Confidentiality — key material *(new; the existing key gates measure only time)*

The only key-material gates today paste an `.atKeys` file into a page and record Argon2id
wall-clock. Nothing tests the property the concern is named for.

| # | Gate | Proves |
| --- | --- | --- |
| X-K1 | After a key write, the IndexedDB record is **not plaintext** | the envelope is actually applied |
| X-K2 | `exportKey` on the wrapping key **throws** | the key is genuinely non-extractable |
| X-K3 | "Ciphertext present, wrapping key missing" raises a **distinct documented error code**, not a generic decrypt failure | the eviction case is handled, not merely survived |
| X-K4 | Generate → store → reload → retrieve → decrypt round-trips in **Chrome *and* Safari** | Safari's storage policy is the risk; this gate blocks the key-storage design from being treated as approved |

### 9a.2 Remote-only correctness *(new — D-12, D-13)*

| # | Gate | Proves |
| --- | --- | --- |
| X-R1 | A remote-only client constructs with **no Hive box and no SQLite** in the process — including on the **write** path | the injected secondary never reaches the lazily-opened sync queue. This is the D-13 regression |
| X-R2 | A remote-only client **reads data written by a local-storage client** | unstamped keys route to the legacy provider on read; without this the client writes fine and fails on pre-existing data |
| X-R3 | A write is not acknowledged until the atServer accepts it | write-through, not write-back — no reintroduced durability question |
| X-R4 | Notification resume across two sequential clients does not replay | under D-13 the checkpoint read **silently succeeds and returns nothing**, so this is a correctness bug rather than a crash. If in-memory is chosen instead, the gate is an explicit test *documenting* the replay |
| X-R5 | Two clients for two different atSigns coexist in one process with independent caches | D-18 multi-tenancy, demonstrated rather than promised |

### 9a.3 Deployment contract *(new — the environment the other gates assume)*

| # | Gate | Proves |
| --- | --- | --- |
| X-D1 | The host page is served over **HTTPS or localhost** | `crypto.subtle` exists. Every crypto and key-storage measurement is invalid without it — on plain http they would report the design as broken and every primitive as pure Dart |
| X-D2 | Response headers include `script-src 'wasm-unsafe-eval'` and `application/wasm`, verified against the deployed artifact | the contract is executable, not aspirational |
| X-D3 | `COOP`/`COEP` are **absent** | D-17 — cross-origin isolation would break popup OIDC, and nothing in V1 needs it |

### 9a.4 Surface stability *(new — D-15)*

| # | Gate | Proves |
| --- | --- | --- |
| X-S1 | Every method on the JS/TS surface returns a `Promise` — a **surface** test, not a behaviour test | the V2 storage upgrade cannot become a breaking npm change (D-15) |
| X-S2 | `dist/index.js` and `dist/index.d.ts` are **generated**, and a clean rebuild produces no diff | D-19 — the shipped behaviour and the published types cannot drift, because neither is hand-maintained |
| X-S3 | A **timeout-bounded** Node smoke test resolves a real call | the shim ordering trap is a silent hang, not an error; a bare `await` cannot tell a hang from slowness |

### 9a.5 A standing rule for every tier

**Classify each failure before acting on it:**

- **bucket (a)** — harness or platform artefact
- **bucket (b)** — genuine algorithm or protocol output mismatch

**Bucket (b) is a stop condition.** Without this triage, `@TestOn('vm')` annotations
silently convert evidence into exclusions, and a `continue-on-error` tier reports green
while the thing it was built to detect goes unrecorded.

---

## 10. The honest limit

**No gate here proves "zero runtime failures".** Stating otherwise would be the same
mistake the predecessor doc made with the compiler.

What the ladder does establish is narrower and stronger where it counts:

- **T0 makes neutrality structural rather than sampled.** If `dart:io` is not in the
  reachable graph, no call stack can reach it — regardless of which paths the tests
  happen to exercise. This is the load-bearing guarantee.
- **T2/T3 catch the residual**: code that is neutral and still wrong under WasmGC —
  integer width, encoding, async ordering, third-party behaviour differences.
- **T4 catches integration**: the parts that only fail against a real server.
- **T6 catches boundary infidelity**: a value that crosses to JavaScript as something
  other than what the TypeScript signature promised. Its two headline defects are silent
  (a killed process, a permanently pending Promise), so T6.2 and T6.3 are the gates that
  make them loud.

The gap that remains is portable-but-wrong logic on a path no test covers. T0 cannot
see it and T2 does not reach it. That gap is bounded by the T2 coverage floor and
should be reported as a number, not described as closed.
