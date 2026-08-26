# Roadmap & high-level design — an implementation-neutral `AtClient`

**Status:** design source of truth (high-level WHY + WHAT). Companion docs carry the
seam designs, the build sequence, the acceptance gates, and the decision log.
**Scope:** making `AtClient` — and every package beneath it — free of platform
implementations, so that a browser WasmGC build runs without runtime failures. The
`at_client_web` platform package is the first consumer of the result.
**Written against:** `trunk` at `20f7f4da5`, 2026-08-13. Supersedes the single-file
`plan.md` (removed; recoverable from git history at `33a062a61`).

> This doc is the **high-level WHY + WHAT** only: the neutrality thesis, the tier
> model, goals/non-goals, the ownership boundary against the PQ program, and the
> phase trajectory. When a companion disagrees on design *intent*, this document
> wins; for mechanics, sequencing, gates, or rulings the companion named below is
> authoritative.

## Table of contents

- [Document map](#document-map)
- [1. The thesis](#1-the-thesis)
- [2. Why the compiler cannot be the gate](#2-why-the-compiler-cannot-be-the-gate)
- [3. The tier model](#3-the-tier-model)
- [4. Goals and non-goals](#4-goals-and-non-goals)
- [5. Ownership boundary against the PQ program](#5-ownership-boundary-against-the-pq-program)
- [6. The phase trajectory at a glance](#6-the-phase-trajectory-at-a-glance)

## Document map

This is one of **six** docs. Each keeps to its lane; cross-references point at the
canonical home rather than duplicating it.

| Doc                                                | What lives there                                                                                                                                                                                                                                                                                           |
| -------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **roadmap.md** (this doc)                          | The WHY + WHAT — the neutrality thesis, the compiler-blindness finding, the three-tier model, goals/non-goals, the PQ ownership boundary, the phase trajectory.                                                                                                                                            |
| [`design.md`](design.md)                           | The per-capability seam designs — transport, storage bootstrap, sync queue, keys, HTTP, connectivity, logging, filesystem, process/env. Current call sites with `file:line`, the proposed interface, and who implements it on each platform. Plus the dead-end seams and the `AtClientPreference` reframe. |
| [`implementation-plan.md`](implementation-plan.md) | The build sequence — phases, the task backlog (P/T/I/C/G/D groups), dependency order, and the publish ladder.                                                                                                                                                                                              |
| [`acceptance.md`](acceptance.md)                   | The gates, tiered T0–T5, with the measured evidence for each and an explicit statement of what each tier does *not* prove.                                                                                                                                                                                 |
| [`decisions.md`](decisions.md)                     | The decision log — the binding rulings (D-1..D-9), their rationale, the measured findings that drove them, and the open questions.                                                                                                                                                                         |
| [`js-api.md`](js-api.md)                           | The non-Dart consumer story — the dart2js compile target, the measured JS/TS language boundary, the TypeScript surface, error mapping, TS-supplied implementations, Node, and npm packaging.                                                                                                               |

---

## 1. The thesis

**`at_client` and every package beneath it hold interfaces, not implementations.**

No `dart:io`. No `dart:ffi`. And — the part that distinguishes this plan from its
predecessor — **no platform conditionals either**. A core package must not know that
platforms differ. Platform-specific behaviour is supplied from outside, by a platform
implementer package, through an injected interface.

The tiers:

```
at_client / at_lookup / at_utils / at_auth / at_chops     ← interfaces only
        ▲                    ▲                    ▲
at_client_web           *_io barrels         at_client_flutter
(WebSocket,            (SecureSocket,        (keychain, app dirs)
 SQLite-wasm,           file keystore,       — a consumer today,
 IndexedDB keys)        file logging)          an implementer later
```

**Why not conditional imports.** A conditional import is a compile-time answer to a
runtime question. It leaves platform knowledge inside the neutral layer, it makes the
core's dependency graph platform-dependent, and its non-native branch is a stub —
which is the exact failure this project exists to eliminate. See
[`decisions.md`](decisions.md) D-1 and D-2.

**The goal is no runtime failures, not a clean compile.** A build that compiles and
then throws the first time a call stack reaches storage is a failed port that reports
success. The canonical example lives in this repo today:
`at_client/lib/src/sync/at_sync_queue.dart:121` opens a global Hive box lazily, on the
first `put` — not at construction. Nothing about compiling the client reveals it.

## 2. Why the compiler cannot be the gate

The predecessor doc asserted: *"No `dart:io`. The compiler hard-errors if any
reachable code transitively imports it."*

**That is false on Dart 3.12.** Measured 2026-08-13 on Dart SDK 3.12.0 (stable),
`dart compile wasm` against a program with a reachable, non-tree-shakeable
`File.existsSync()` and `Platform.pathSeparator`:

| Library        | `dart compile wasm`                                                      | Runtime                                                     |
| -------------- | ------------------------------------------------------------------------ | ----------------------------------------------------------- |
| `dart:io`      | **exit 0**, module produced                                              | **throws** `Unsupported operation: _Namespace` on first use |
| `dart:isolate` | **exit 0**, module produced                                              | —                                                           |
| `dart:ffi`     | rejected — *"Dart library 'dart:ffi' is not available on this platform"* | —                                                           |
| `dart:html`    | rejected                                                                 | —                                                           |
| `dart:js`      | rejected                                                                 | —                                                           |
| `dart:mirrors` | rejected                                                                 | —                                                           |

The compiled module was executed under Node 24.18 to confirm the runtime half.
Full method in [`acceptance.md`](acceptance.md).

This is the single most consequential fact in the project, and it has three
consequences:

1. **A green `dart compile wasm` proves almost nothing** about the two libraries that
   dominate our port surface. It catches `dart:ffi` (the at_chops island) and the
   legacy web libraries, and nothing else.
2. **The structural gate is primary, not supplementary.** Only a dependency-tree walk
   can establish that `dart:io` is absent from the graph, because the toolchain will
   never say so. See [`acceptance.md`](acceptance.md) T0.
3. **Structural absence is a stronger claim than tested success.** If `dart:io` is not
   in the reachable graph at all, no stack can reach it. That is why the thesis is
   framed as neutrality rather than as coverage.

## 3. The tier model

### Tier 1 — the neutral core

`at_client`, `at_lookup`, `at_utils`, `at_auth`, `at_chops`, `at_commons`,
`at_contact`, `at_policy`, `at_server_status`. Interfaces, models, protocol logic,
pure-Dart crypto. Zero platform libraries, zero `if (dart.library.*)`, zero throwing
fallbacks.

### Tier 2 — the `_io` barrels

Native implementations ship as an additional barrel *inside the same package* —
`at_lookup_io.dart`, `at_utils_io.dart`, `at_client_io.dart` — mirroring the
`at_auth_io.dart` precedent set by the PQ program's S-5. This keeps the native code
where it already lives (no relocation, no new packages), while removing it from the
neutral barrel's import graph. Consumers add one import.

### Tier 3 — platform implementers

- **`at_client_web`** — new, built by this project. WebSocket transport, SQLite-wasm
  storage, IndexedDB-backed key store, `navigator.onLine` connectivity, console
  logging.
- **`at_client_flutter`** — exists, but is **not** a platform implementer today. It
  implements exactly one abstraction (`KeychainAtKeysIo extends WrittenAtKeysIo`,
  `packages/at_client_flutter/lib/src/keychain/keychain_io_impl.dart:10`); all path
  and preference wiring lives in *app* code under `example/`. In this project it is a
  breaking-change **consumer**. Promoting it to a true implementer is deferred.
- **`at_client_cli`** — does not exist. `at_onboarding_cli` and `at_cli_commons`
  perform the role informally (`home_directory_util.dart`, the duplicated
  `ServiceFactoryWithNoOpSyncService`). Extracting a real package is deferred; until
  then they consume the Tier-2 `_io` barrels.

### Tier 4 — non-Dart consumers

A JavaScript/TypeScript facade compiled from `at_client_web`'s own entry point and
published to npm. Design in [`js-api.md`](js-api.md); rulings D-7..D-9 in
[`decisions.md`](decisions.md).

```
        JS / TS apps  (npm: browser SPA · Node service · TS agent)
                    ▲
        the @JSExport facade — packages/at_client_web/lib/src/js/
                    ▲
at_client_web      *_io barrels      at_client_flutter
                    ▲
        at_client / at_lookup / at_utils / at_auth / at_chops
```

Two things about this tier are worth stating at roadmap level:

- **It adds no Dart package.** The facade is an entry point inside `at_client_web`, and
  the npm artifact is a build output, not a pub package — so D-4 stands unamended.
- **Node is a target, not just the browser.** Node supplies `WebSocket`,
  `crypto.subtle`, `fetch` and `navigator`, but **no `indexedDB` and no `localStorage`**,
  so a Node consumer supplies storage from TypeScript. This works because a JS object can
  satisfy a Dart interface — measured — which means the injection seams this project
  builds are reachable from TypeScript, and no Dart `at_client_node` is needed.

## 4. Goals and non-goals

### Goals

1. **A neutral core.** No file reachable from `package:at_client/at_client.dart`,
   `at_lookup.dart`, `at_utils.dart` or `at_chops.dart` imports a platform library or
   resolves a platform conditional. Enforced structurally, in CI.
2. **No runtime failures on web.** The client's logic executes under a WasmGC
   embedding — verified by running the test suites there, not by compiling them.
3. **`at_client_web` exists** and drives a real atServer from a browser: onboard,
   read, write, sync, share cross-atSign.
4. **Behavioural non-regression on native.** Native code paths keep their current
   behaviour, and the native suites stay green at every commit boundary.
5. **Storage work advances the native roadmap.** The web SQLite path is an additional
   open strategy under the same `SqliteDatabase`, not a parallel backend.

Goal 4 is **behavioural, not API-level**. Neutrality requires removing native defaults
(`atKeysIo ??= FileAtKeysIo()`, `atServerStatus ??= AtStatusImpl(...)`, the hardcoded
`HiveAtPersistenceFactory`, `Socket getSocket()` on `AtConnection`). Those are breaking
changes and are accepted as such — [`decisions.md`](decisions.md) D-3.

### Non-goals

- **WASI.** No Dart→WASI toolchain exists. Both Dart web compilers target the browser's
  JS embedding, and that is the spec.

> **On the project's name.** "WASM" names the effort, not the deliverable. The product is
> an implementation-neutral client that runs outside a Dart VM; *which* web compiler emits
> it is a packaging decision made at the end. [`decisions.md`](decisions.md) D-7 selects
> **dart2js** for the JS/TS artifact and keeps dart2wasm open at zero cost, because the
> source is identical for both. Neutrality is required either way — measured, `dart:io`
> compiles and then throws under both compilers.
- **Flutter web / Flutter WASM.** A separate, unsupported track. `at_client_flutter`
  is in scope only as a consumer of the breaking majors.
- **CLI packages as a port target.** `at_onboarding_cli` and `at_cli_commons` never
  enter a WASM build graph. They are in scope only as consumers.
- **Server-side changes.** None are required; the atServer already accepts WebSocket
  connections on the Atsign Protocol port — [`design.md`](design.md) §1.
- **File transfer on web** in the first milestone.
- **A `Clock` / `RandomSource` seam.** `DateTime.now()`, `Timer` and `Uuid` are
  portable under WASM. Injecting them is a testability win, not a port requirement,
  and is deliberately kept off this critical path.

## 5. Ownership boundary against the PQ program

`at_auth`'s WASM split is **owned by the PQ program**, not by this project:
projects **S-5** (at_auth 4.0.0 — the `at_auth_io.dart` barrel, dropping the
`FileAtKeysIo` default, registrar onto `package:http`) and **S-6** (consumer bumps),
at [`../pq/implementation-plan.md`](../pq/implementation-plan.md) — ⚠️ this cited
**lines 312–339**, and a line number is not an address: that plan was restructured
on 2026-08-26 and the range now lands on unrelated prose. Find S-5 and S-6 by name
in [`../pq/detail/implementation-plan.md`](../pq/detail/implementation-plan.md).
That
plan explicitly names *this* effort as the separate "wasm-port" that owns
`at_lookup` and `at_chops`.

This project therefore owns: `at_lookup`, `at_client`, `at_utils`,
`at_server_status`, the at_chops dependency verification, the persistence work in
`at_server`, and `at_client_web`. It **depends on** S-5 rather than duplicating it.

`at_auth` also sets the pattern this project follows — the `_io` barrel shape, and the
ruling that a removed default is preferable to a conditional default.

## 6. The phase trajectory at a glance

| Phase                   | What lands                                                                                                                         | Gate it turns on |
| ----------------------- | ---------------------------------------------------------------------------------------------------------------------------------- | ---------------- |
| **0 — Ratchet**         | The structural dependency-tree walk, per core package, in CI. Baselined against today's violations so it can only shrink.          | T0               |
| **1 — Cheap seams**     | Plumb the four seams that already exist and are never passed through; delete `sync_isolate_manager.dart`; fix `at_server_status`.  | T0 shrinks       |
| **2 — Transport**       | `AtTransport`; `Socket getSocket()` removed; `at_lookup_io.dart`; `at_lookup` 4.0.0.                                               | T0 for at_lookup |
| **3 — Storage**         | Web SQLite open path in `at_persistence_secondary_server`; selectable backend; backend-neutral `AtSyncQueue`.                      | T2 for storage   |
| **4 — Sweep**           | `at_utils` barrel split, connectivity, file transfer off the reachable surface; `at_client` 4.0.0.                                 | T0 green, T1, T2 |
| **5 — `at_client_web`** | The platform package; first live browser session.                                                                                  | T3, T4           |
| **6 — JS/TS facade**    | The `@JSExport` facade and its entry point inside `at_client_web`; the npm package. See [`js-api.md`](js-api.md).                  | T6               |
| **7 — Deferred**        | File transfer on web, browser onboarding UX, Argon2id performance, the `at_client_cli` / `at_client_flutter` implementer packages. | —                |

Phases 2 and 3 are independent and can run in parallel. Phase 0 gates everything,
because without it each phase's gains decay behind the next one.
