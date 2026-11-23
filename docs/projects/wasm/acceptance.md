# acceptance.md — The gates, and what each one actually proves

**Status:** acceptance catalogue (binding). Lives in `docs/projects/wasm/`.
**Purpose:** the tiered gate ladder **T0–T6** for the implementation-neutral
`AtClient` work, the measured evidence behind each tier, and — for every tier — an
explicit statement of what it does *not* establish.
**Status refreshed:** 2026-08-27, against `trunk` at `9d9e5f7d7`; T9 (the app-supplied
transport) landed on `gkc-client-lifecycle` on 2026-09-13. §9a.1 amended 2026-10-18 for
the per-passkey record design (K-1..K-9) and 2026-10-27 for K-10/K-11 and unrevoke; T3.1 re-pointed to the SimpleOPFS VFS (D-26) 2026-10-18; no gate was re-measured on those passes. The measured
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

**A conditional in a gated package must have both of its branches walked.** The ratchet
resolves web-side, which covers one branch. A `control` resolves with io semantics by
default, so pointing one at the same barrel covers the other — and `environment: web` on a
control pins the web branch where that is the half in question. Absent the second walk,
the ratchet passes just as convincingly when the conditional was skipped and neither
branch was seen. Put the control on the file axis — `reaches_file` naming the native
branch's file — because a barrel under io resolution usually reaches `dart:io` through
other files as well, and `reaches_library` would prove nothing there.

This is not a ban on `if (dart.library.`: a conditional whose two branches are both real
implementations, with a recorded reason why one cannot serve both platforms, is allowed.
See [`decisions.md`](decisions.md) D-1 and OQ-1.

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
| T3.1 | `dart test -p chrome -c dart2wasm` green for the `at_client_web` storage backend, including a write/reload/read cycle against the SimpleOPFS VFS (D-26). **V2** — the V1 default bundle has no storage backend (D-17). | All tests pass. |
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
| T6.1 | The compiled artifact loads under Node and in a browser, and the facade object is reachable with the expected method names.                                | Object present; method set matches the `.d.ts`. Browser compilation and wrapper surface are covered by `test/web/compile_test.dart` (covering both `at_client_web_entry.dart` and `at_client_bridge_entry.dart`) and `test/js/bridge_test.dart` (Chrome); Node load and npm smoke test live in `packages/at_client_web` of [at_js](https://github.com/atsign-foundation/at_js) (not on `at_js` trunk yet). |
| T6.2 | **Every** exported async method settles within a fixed timeout — resolve or reject, never pending.                                                         | All settle. Browser bridge settlement is exercised by `test/js/bridge_test.dart` and `test/js/bridge_wiring_test.dart` (Chrome); Node settlement under the dart2js scheduler shim awaits `at_js` tests. |
| T6.3 | **No unconverted `Future`, `Stream`, `List`, `Uint8List`, `CItem`, `CEvent` or `Predicate` escapes the facade.** Static check over `lib/src/js/`: every exported member returns a JS type. | Zero violations. Enforced by `test/js/export_boundary_test.dart` (methods, getters, setters, fields, and nested comments/strings) and verified at runtime for null-prototype item data in `test/js/bridge_test.dart`. |
| T6.4 | Every thrown Dart exception arrives as a catchable `AtError` with a stable `code`, never as the default boxed rejection. **Includes `CollectionOpException`/`OpFailure`** — a batch partial-failure must arrive as the same `AtError` shape, not a second result-union type ([`js-api.md`](js-api.md) §6). | Mapped for every exception class the facade can raise, `CollectionOpException` included; the generic message appears nowhere. Tests: `test/js/at_error_code_test.dart`, `test/js/bridge_test.dart` ("a collection failure rejects with its code and fields (T6.4)"), and `test/js/bridge_wiring_test.dart`. |
| T6.5 | `watch`, `subscribe`, and `onStatus` deliver events and stop delivering after unsubscribe or `close()`.                                                      | Events observed, then none after cancel or `close()`. Met in Dart/Chrome by `test/js/bridge_test.dart`, `test/js/js_session_test.dart`, and `test/js/bridge_wiring_test.dart`; `at_js` wrapper tests live in `packages/at_client_web/test/client.test.ts` (not on `at_js` trunk yet). |
| T6.6 | A TypeScript-supplied `KeyStore` satisfies the Dart interface and round-trips a value.                                                                     | Round-trip succeeds. This is the Node storage path ([`js-api.md`](js-api.md) §7); not in the alpha (`js-api.md` §5a). |
| T6.7 | The published `.d.ts` type-checks against a sample TS consumer that exercises the whole surface.                                                           | `tsc --noEmit` clean. Lives in `at_js` (`packages/at_client_web`); keep aligned with `js-api.md` §6.1–§6.2. |
| T6.8 | **An unknown `CEvent` subtype reaches the JS consumer as a generic `'unknown'` event, not dropped and not thrown.** `CEvent` is deliberately not `sealed` upstream (`collections.dart:5077`) — a future minor can add a subtype the encoder does not yet know. | A synthetic unrecognised subtype (test-only) round-trips to `'unknown'`. Tests: `test/collections/js_collections_adapter_test.dart` and `test/js/bridge_test.dart` ("collection watch delivers events, including unknown, and unsubscribes (T6.5, T6.8)"). |
| T6.9 | **A record written by the JS facade carries its declared `typeTag` on the wire**, not `'n/a'`. Regression guard for `decisions.md` §2.6 F3/D-11 — the write-compatibility gap the whole collections design has to solve for. | Met: `test/collections/js_collections_adapter_test.dart` verifies the adapter writes the declared tag on the wire, `test/js/bridge_test.dart` checks `type` reaches the session, and `test/js/bridge_wiring_test.dart` proves end-to-end (`AtClientWebBridge` -> `AtClientJsSession` -> `JsCollectionsAdapter` -> `AtCollection`) that the declared `type` tag lands on the wire. |

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

These follow from D-17..D-22. Three of them close holes where the existing ladder measured
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

**Amended 2026-10-18 — K-1..K-9 change what X-K1..X-K4 mean and add X-K5..X-K9; the 2026-10-21 revocation ruling adds X-K10; the 2026-10-27 K-10/K-11 and unrevoke rulings amend X-K9 and X-K10 and add X-K11..X-K14; the 2026-10-27 K-5 re-ruling amends X-K7; the 2026-10-27 K-12 ruling amends X-K5, X-K9 and X-K13; the 2026-10-28 K-13 ruling adds X-K15..X-K19; the 2026-11-05 K-18 ruling (amended 2026-11-06) amends X-K9 (the atSign typed once; another passkey or atSign on no pointer, `AT0027` or `AT0028`) and X-K19 (the hint gains the atSign).** Under the K-10 pointer and K-11 document ([`browser-onboarding.md`](browser-onboarding.md)) there is no stored wrapping key to be non-extractable or to go missing: the kek is re-derived from the PRF output on every open, and IndexedDB holds only the credential hint. Read X-K1 as "nothing in IndexedDB holds @keys in plaintext", X-K2 as "the derived kek is imported non-extractable", X-K3 as "a credential hint present with no passkey available (cleared passkey, unsupported browser) raises a distinct documented error", and X-K4 as "enroll → reload → open round-trips in Chrome *and* Safari". None of the new gates below is built (X-K15..X-K19 included: none built).

**Session custody.** The passkey vault (the auth seed) and the APKAM key are held by the passkey session while its client runs; the session closes the vault once the client stops, and `AtClient.stop()` closes no key store. The auth seed is zeroed as soon as the APKAM key pair is derived from it, before PKAM, and closing the vault zeroes what it can. The client's key store holds the APKAM pair for the session (private half as bytes, zeroed when the store closes; the authenticator's `String` copy, the immutable `String` copies made while the key is encoded for a read, and the @keys private keys cannot be wiped in Dart), serves reads from memory, and never stores the APKAM private key or the enrollment's own public authentication key in the document. The claim covers buffers the client holds, not copies the browser or the JS runtime made. X-K2 reads as K-10/K-11 (2026-10-27) rule it: the kek is never stored, is re-derived on each open and is imported non-exportable (X-K20 gates the key's flags, D-29). X-K15 and X-K16 are deferred by K-16 and the gate-(c) scope (review-response plan, 2026-11-12). X-K4 (Safari), X-K8 and the server side of X-K10..X-K14 stay open as gate-(c) blockers.

| # | Gate | Proves |
| --- | --- | --- |
| X-K5 | HKDF with `P` = bytes `00..1f`, atSign `@alice` and the `at_auth/custody/<name>/v1` labels yields the lookup key, ns, kek and authSeed in [`atkeys-derivation.md`](atkeys-derivation.md), on the Dart VM and in the browser, under dart2js and dart2wasm, and `@Alice`, `alice`, `@ali.ce` yield the same | K-1, K-3, K-12: the derivation and atSign canonicalisation are stable across implementations |
| X-K6 | A record whose `v`, `typ`, `alg`, `kdf` or `iv` was edited fails to open | K-4: the AAD binds the clear header (downgrade) |
| X-K7 | After PKAM, a valid older document whose public keys no longer match the published ones (`public:publickey@<atSign>`) fails hard after it is opened and before the restored @keys are used for any encrypt or decrypt; the same applies on return (3.2) and recovery (3.3), except that a login without saved hints whose onboarding's completion-due record says the onboarding's own delete of the CRAM secret answered publishes the document's key over the published one ([`browser-onboarding.md` section 3.8](browser-onboarding.md#38-app-guidance-a-failed-or-cancelled-passkey-prompt)) | K-5 (re-ruled 2026-10-27, amended 2026-11-19): partial rollback. Not tested, by design: a joint rollback of document and published keys, or a stale-but-valid document with unchanged public keys (K-5 limits) |
| X-K8 | PRF returns 32 bytes on create and get, and the record opens after a reload, on iOS Safari, Firefox and Windows Hello | K-7: today 4 of 4 rows (Chrome, Safari and Brave on macOS, Brave on Android) pass; these three are untested |
| X-K9 | After a successful open the credential hint is rewritten and `navigator.storage.persist()` is requested once; with IndexedDB cleared, the passkey and the atSign, typed once (K-18), restore the session (pointer → PKAM with the APKAM key re-derived from `P` → document → K-5 match, or X-K7's exception) and are the only inputs. A passkey whose pointer is missing or whose PKAM is refused (`AT0027` revoked, `AT0028` deleted) lets the user pick another passkey or atSign | K-6 clarification, retained under K-10/K-11, and K-12: eviction is a UX cost, not a loss, on the primary path. The K-12 fallbacks are ruled by K-13 and gated in X-K15..X-K19 |
| X-K10 | A revoked enrollment's PKAM is refused with `AT0027` until an approver unrevokes it; a new `enroll:request` with the same APKAM public key is refused with `AT0032`, asserted on the message text `The apkamPublicKey is already held by another enrollment` (the code `AT0032` is also returned for a duplicate appName + deviceName) | revocation (2026-10-21): same-key re-enroll needs approver action |
| X-K11 | The enrolling client writes the pointer `public:_<lookupHex>.<ns>@<atSign>` exactly once with no TTL and no `ttr` (write-once is client behaviour); another enrollment of the same atSign, lacking `<ns>:rw`, cannot update or delete it (`AT0009`); a foreign `plookup` leaves no `cached:` copy; the pointer is readable by unauthenticated `lookup:` on the atSign's own atServer, opens only as `typ:"eid"`, and is absent from every `scan` (owner, `showhidden:true`, CRAM, APKAM, unauthenticated) | K-10, K-17 |
| X-K12 | The document `atkeys.<eid>.a.__e@<atSign>` is read and written over PKAM by its enrollment; another enrollment is refused; CRAM can read it but its write is refused; it opens only as `typ:"atkeys"` and holds no APKAM private key; it is listed by its own enrollment's and CRAM's scans (not hidden) | K-11 |
| X-K13 | After revoke the document is unreadable; after `enroll:unrevoke` by CRAM or a `__manage` holder with all target namespaces, the same `enrollmentId` PKAMs again with the same APKAM key, re-derived from the same passkey (K-12), keeps its original expiry, and reads the document; unrevoke of an expired enrollment fails with `AT0028`; `enroll:approve` on a revoked enrollment is refused. Note: unrevoke of an enrollment revoked by cascade is refused while its approver stays revoked, and passes once that approver is deleted (EVH:930-946) | R-a: re-enroll after revoke = unrevoke |
| X-K14 | Unrevoke of an enrollment does not reinstate the enrollments it approved that the revoke cascaded to | revoke cascade is not undone |
| X-K15 | **Deferred (K-16): not a gate for the PRF-only release.** **Given** an authenticator without PRF enrolled with a passphrase, **when** the browser storage is cleared and the passphrase is entered, **then** the passphrase-sealed record is fetched by lookup hash without PKAM, unsealed, and the session is restored (PKAM → document → K-5 match, or X-K7's exception) | K-13 a: no-PRF restore, no bootstrap loop |
| X-K16 | **Deferred (K-16): not a gate for the PRF-only release.** **Given** the no-PRF record, **when** a wrong passphrase is entered, **then** unsealing fails closed: no PKAM attempt, no @keys exposed | K-13 a |
| X-K17 | **Given** a lost or wiped passkey, **when** restore is attempted for the old enrollment, **then** it cannot be restored; **when** the user enrolls fresh (OTP + approver) and an approver revokes the old enrollment, **then** the new enrollment opens and the old enrollment's PKAM is refused (`AT0027`) | K-13 b: passkey gone = enrollment gone; no recovery path |
| X-K18 | **Given** a second passkey (another device), **when** it derives its keys, **then** they differ from the first passkey's (a different PKAM key and lookup id), so it cannot open the first passkey's records. This proves the derived keys differ; it does not cover the OTP + approval enrollment flow | K-13 d: PRF output differs per credential; not a backup |
| X-K19 | **Given** any open or restore (PRF or no-PRF), **when** every browser store this package writes is inspected (IndexedDB and `localStorage`), **then** IndexedDB holds only the hint (`atSign`, `credentialId`, `enrollmentId`; K-18 adds the atSign) and `localStorage` holds at most the PRF-miss timestamp (`at_client_web:prf-miss-at`); `sessionStorage` is empty: no PRF output, auth seed, derived key, @keys or passphrase in any of them, raw, base64 or hex. The package uses no other store (no OPFS, BroadcastChannel, cookie or Cache); its Web Lock name carries only the atSign. The kek is covered by X-K20. The no-PRF case is deferred with K-13 a (K-16). D-32's pending onboarding record was rejected (2026-11-18), so IndexedDB holds no other record. | K-13 c1; c2 rejected, K-12 "never stored" |
| X-K20 | **Given** the browser sealer, **when** its WebCrypto key is inspected in Chrome, **then** `extractable === false` and `usages` are exactly `encrypt` and `decrypt`; `exportKey('raw')` and `exportKey('jwk')` reject; the seal key's bytes handed to `importKey` are zeroes once it is imported | D-29: once imported, the kek can't be read back from WebCrypto; K-10/K-11 (X-K2 reading) |

The key-sources design in [`../key-sources/design.md`](../key-sources/design.md#8-the-browser)
places these gates beside a passkey-derived key and an atServer-held keys document,
where the WebCrypto key becomes a local cache or a fallback.

### 9a.2 Remote-only correctness *(new — D-17, D-18, D-24)*

**Amended 2026-11-13 — D-18 reversed.** Remote-only is a client routing to its atServer (`RemoteLocalPref.remoteOnly`) on `InMemoryAtClientStorage`, not a storage bundle, so X-R1..X-R3 are stated against a `portalSession` client. None of them is built as a gate yet.

| # | Gate | Proves |
| --- | --- | --- |
| X-R1 | A `portalSession` client constructs with **no Hive box and no SQLite** in the process — including on the **write** path | `InMemoryAtClientStorage` holds the keystore and the sync queue; sync runs as usual, starts at every open and pulls the atServer's records into the page without the app asking, and pushes the writes a `remoteOnly` client keeps local (only a put or delete whose request options set `useRemoteAtServer = false` explicitly). The gate is on *this client*, not on the process: a consumer who passes a SQLite storage is expected to open one |
| X-R2 | A `remoteOnly` client **reads data written by a local-storage client** | unstamped keys route to the legacy provider on read; without this the client writes fine and fails on pre-existing data |
| X-R3 | A write is not acknowledged until the atServer accepts it | write-through, not write-back — no reintroduced durability question |
| X-R4a | **connect** — across two sequential clients, the second is delivered nothing sent before its notification service was created | the policy is anchored at service creation, so nothing between creation and `monitor:` is lost either (D-24) |
| X-R4b | **window(1h)** (the browser default until 2026-11-02, now *connect*; D-24 amended) — the second client is delivered only notifications newer than `max(checkpoint, now − 1h)`, and newer than `now − 1h` with no checkpoint store | on `InMemoryAtClientStorage` the watermark is a `local:` key held in memory, so a reload has no checkpoint and starts from the session's creation time (OQ-13, corrected 2026-11-02); the window recovers up to an hour that a reload would otherwise lose |
| X-R4c | **resume** — the second client re-delivers nothing at or before the first client's last notification | the IndexedDB checkpoint record works; required only for a browser client that opts into resume |
| X-R4d | **full** — the second client is delivered every unexpired notification the atServer holds, each once | *full* is bounded by server retention, not a durability promise |
| X-R4e | For every policy, a monitor reconnect within one client delivers every notification sent while it was disconnected, and none twice | the policy decides only where the service starts; a reconnect resumes from the last notification received |
| X-R5 | Two clients for two different atSigns coexist in one process with independent caches | D-22 multi-tenancy, demonstrated rather than promised |

### 9a.3 Deployment contract *(new — the environment the other gates assume)*

| # | Gate | Proves |
| --- | --- | --- |
| X-D1 | The host page is served over **HTTPS or localhost** | `crypto.subtle` exists. Every crypto and key-storage measurement is invalid without it — on plain http they would report the design as broken and every primitive as pure Dart |
| X-D2 | Response headers include `script-src 'wasm-unsafe-eval'` and `application/wasm`, verified against the deployed artifact | the contract is executable, not aspirational |
| X-D3 | `COOP`/`COEP` are **absent** | D-21 — cross-origin isolation would break popup OIDC, and nothing in V1 needs it |

### 9a.4 Surface stability *(new — D-20)*

| # | Gate | Proves |
| --- | --- | --- |
| X-S1 | Every method on the JS/TS surface returns a `Promise` — a **surface** test, not a behaviour test | the V2 storage upgrade cannot become a breaking npm change (D-20) |
| X-S2 | `dist/index.js` and `dist/index.d.ts` are **generated**, and a clean rebuild produces no diff | D-23 — the shipped behaviour and the published types cannot drift, because neither is hand-maintained |
| X-S3 | A **timeout-bounded** Node smoke test resolves a real call | the shim ordering trap is a silent hang, not an error; a bare `await` cannot tell a hang from slowness |

### 9a.5 A standing rule for every tier

**Classify each failure before acting on it:**

- **bucket (a)** — harness or platform artefact
- **bucket (b)** — genuine algorithm or protocol output mismatch

**Bucket (b) is a stop condition.** Without this triage, `@TestOn('vm')` annotations
silently convert evidence into exclusions, and a `continue-on-error` tier reports green
while the thing it was built to detect goes unrecorded.

---

## 9b. Build target and release assets *(new — proposed decision D-36, pending review)*

These gates cover the release plumbing for one declared compile target per bridge
release (proposed decision D-36, pending review). Every row is checkable on a local machine
from `packages/at_client_web` (or the repository root, where the path is named); none
needs a browser, an atServer or a workflow run. `dart` must be a real Dart SDK for the
build rows, except in X-B3 and X-B4, which deliberately use a stub `dart` first on
`PATH`.

| # | Gate | Proves |
| --- | --- | --- |
| X-B1 | **dart2js ships one file.** From a clean build directory, `rm -rf build && bash tool/build.sh at_client_bridge_entry --target dart2js` exits 0, and `test -f build/at_client_web.js && test ! -e build/at_client_web.wasm && test ! -e build/at_client_web.mjs` succeeds. `bash tool/build.sh at_client_bridge_entry --target=dart2js` (the `--target=VALUE` form) behaves the same | The dart2js release builds exactly `at_client_web.js` (published with `at_client_web.js.sha256` and the manifest); a stale wasm bundle from an earlier build cannot ride along |
| X-B2 | **dart2wasm ships the wasm module and its loader.** `rm -rf build && bash tool/build.sh at_client_bridge_entry --target dart2wasm` exits 0, and `test -f build/at_client_web.wasm && test -f build/at_client_web.mjs && test ! -e build/at_client_web.js && test -f build/bridge-manifest.json` succeeds | The dart2wasm release publishes a matched `.wasm`/`.mjs` pair, not a `.wasm` with an older loader and not the dart2js file |
| X-B3 | **A wasm failure is fatal for that target.** With a stub `dart` first on `PATH` that exits 1 on `compile wasm` and 0 otherwise, `bash tool/build.sh at_client_bridge_entry --target dart2wasm` exits 1 and names `dart2wasm compile failed`; the same command with `WASM_REQUIRED=0` in the environment still exits 1, because the target forces the flag. `bash tool/build.sh at_client_bridge_entry --target dart2js` exits 0 under the same stub | A broken advisory target fails its own release instead of publishing a partial bundle, and the default target is untouched by it |
| X-B4 | **The legacy no-argument call still succeeds.** With the same stub (whose `compile js` exits 0 without writing), `bash tool/build.sh` with no arguments exits 0 and prints one `warning: dart2wasm compile failed` line per entry. With a real `dart`, `bash tool/build.sh` with no arguments exits 0 and leaves both `build/at_client.js` and `build/at_client_web.js` (`test -f build/at_client.js && test -f build/at_client_web.js`) | Today's local and CI callers keep both entries and the best-effort dart2wasm, rather than being broken by the new argument |
| X-B5 | **Bad arguments are refused by name.** `bash tool/build.sh --target both`, `bash tool/build.sh --target=`, `bash tool/build.sh --target dart2wasm_x` and `bash tool/build.sh at_client_not_an_entry` each exit 1, and each run's stderr names both `dart2js` and `dart2wasm` (`grep -q dart2js && grep -q dart2wasm`) | A typo or a "build both" habit cannot silently produce a release from an undeclared file set; `both` is only the internal no-argument default |
| X-B6 | **Each target's tag is fixed by the target.** The workflow's tag step maps `dart2js` to `at_client_web-bridge-<sha12>` — byte-identical to the tag every existing bridge release uses — and `dart2wasm` to `at_client_web-bridge-wasm-<sha12>`; run its `case` block locally with `TARGET=dart2js` and `TARGET=dart2wasm` and compare the prefixes, and `git tag -l 'at_client_web-bridge-*'` still matches the dart2js releases | A tag keeps meaning one file set: a wasm bundle cannot overwrite, or be mistaken for, the dart2js release for the same commit, and no already-published tag changes meaning |
| X-B7 | **One checksum covers every asset and the manifest, and attestation covers the same files.** `bash tool/build.sh at_client_bridge_entry --target dart2js && cd build && sha256sum at_client_web.js bridge-manifest.json > SHA256SUMS && sha256sum -c SHA256SUMS` passes, as does the dart2wasm equivalent (`sha256sum at_client_web.wasm at_client_web.mjs bridge-manifest.json > SHA256SUMS`); `grep -c 'uses: actions/attest-build-provenance' .github/workflows/at_client_web_bridge_release.yaml` is 2, one gated on each target, and each `subject-path` lists that target's assets, `bridge/bridge-manifest.json` and `bridge/SHA256SUMS` (the dart2js one also lists `bridge/at_client_web.js.sha256`); `grep -n 'sha256sum -c SHA256SUMS'` finds the release job's verification, and the dart2js path also runs `sha256sum -c at_client_web.js.sha256` | The one published `SHA256SUMS` lists every published asset of the target plus the manifest, the download is checked against it (and against `at_client_web.js.sha256` for dart2js), and every published file is attested |
| X-B8 | **The bridge manifest ships with both targets.** `tool/build.sh` writes `build/bridge-manifest.json` before compiling, for either `--target`, and `cmp build/bridge-manifest.json bridge-manifest.json` succeeds after each (the bytes do not depend on the target). The release workflow runs the same `cmp` after the build, lists `bridge-manifest.json` among both targets' uploaded, attested and attached files, and `grep -c 'bridge-manifest.json' .github/workflows/at_client_web_bridge_release.yaml` is at least 6; the dart2js release also still attaches `at_client_web.js.sha256` | A release cannot publish a manifest that differs from the committed one, and the manifest is checksummed and attested like every other asset |

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
