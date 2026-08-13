# decisions.md — Rulings, measured findings & open questions

**Status:** decision record (binding).
**Scope:** the rulings D-1..D-6 that govern the implementation-neutral `AtClient`
work, the measurements that drove them, the superseded positions from the predecessor
`plan.md`, the open questions, and a dated log.
**Lane:** this doc owns *why*, not *how* or *when*. Mechanics live in
[`design.md`](design.md); sequencing in [`implementation-plan.md`](implementation-plan.md);
gates in [`acceptance.md`](acceptance.md); the thesis in [`roadmap.md`](roadmap.md).

## Table of contents

- [1. The rulings](#1-the-rulings)
- [2. Measured findings](#2-measured-findings)
- [3. Superseded positions](#3-superseded-positions)
- [4. Corrections to the predecessor doc](#4-corrections-to-the-predecessor-doc)
- [5. Open questions](#5-open-questions)
- [6. Decision log](#6-decision-log)

---

## 1. The rulings

### D-1 — Injection over conditional imports (2026-08-13)

**A neutral package contains zero `if (dart.library.*)`.** Platform-specific behaviour
is supplied from outside through an injected interface, implemented by an `_io` barrel
or a platform package.

**Why.** A conditional import is a compile-time answer to a runtime question. It keeps
platform knowledge inside the layer that is supposed to be neutral, it makes the core's
dependency graph platform-dependent, and its non-native branch is a stub — the failure
mode this project exists to remove. Injection also puts the platform code where the
platform knowledge is, which is the whole point of having platform packages.

**Cost, stated honestly.** Conditional imports are cheaper and non-breaking. Injection
is neither. D-3 accepts that cost deliberately.

**Scope.** Applies to `at_client`, `at_lookup`, `at_utils`, `at_chops` and
`at_server_status`. `at_auth` is governed by the PQ program (§5, OQ-1).

### D-2 — No throwing stubs (2026-08-13)

**A capability a platform lacks must be unreachable there, not reachable-and-explosive.**
`throw UnsupportedError` in a core platform-capability fallback is a defect, not a port.

**Why.** It is precisely the "compiles but fails at runtime" outcome, hand-written. A
stub converts a build error into a production error and moves the discovery point from
CI to a user.

Enforced by [`acceptance.md`](acceptance.md) T0.4, with an explicit allow-list for
legitimate uses (e.g. a read-only `AtKeysIo` subtype refusing `write`).

### D-3 — Breaking majors are accepted (2026-08-13)

`at_lookup` 4.x, `at_client` 4.x and `at_utils` 4.x are expected. Specifically:

- `Socket getSocket()` leaves `AtConnection`
- `atServerStatus ??= AtStatusImpl(...)` and the hardcoded `HiveAtPersistenceFactory`
  are removed
- `dart:io File` leaves the `AtClient` public surface
- `at_utils.dart` stops exporting `pseudo_server_socket.dart` and `app_config.dart`

**Why.** D-1 rule 2 — a default that names an implementation re-imports the native
graph regardless of what the caller injects. There is no additive way to remove a
default, so neutrality is unreachable without a break.

**Precedent.** The PQ program already took this decision for `at_auth` 4.0.0 (S-5):
drop the `FileAtKeysIo` default, require injection. Consistency across the SDK argues
for the same shape everywhere.

**Bound.** "No regression on native" remains a **behavioural** commitment — native code
paths keep their current behaviour and the native suites stay green. It is explicitly
not an API-compatibility commitment.

### D-4 — `at_client_web` is the only new package for now (2026-08-13)

Flutter and CLI platform-implementer packages are named as the eventual shape and
deferred. `at_client_flutter` is in scope as a breaking-change **consumer**;
`at_onboarding_cli` and `at_cli_commons` likewise.

**Why.** The web implementations have no home today and must be built. The native ones
already exist and work; relocating them into new packages is churn that buys nothing
this project needs.

### D-5 — Native implementations live in `_io` barrels, not new packages (2026-08-13)

Each neutral package gains a second barrel — `at_lookup_io.dart`, `at_utils_io.dart`,
`at_client_io.dart` — exporting the neutral barrel plus the native implementations.

**Why.** This is the seam D-3 requires and D-4 declines to build a package for. It
resolves the tension directly: the native code stays where it already lives (no
relocation, no new pubspecs, no dependency-direction problems), while leaving the
neutral barrel's import graph clean. Consumers add one import line.

**Precedent:** `at_auth_io.dart` under the PQ program's S-5, and the existing
`at_chops.dart` / `at_chops_ffi.dart` pair, which has held its separation successfully.

### D-6 — The structural gate is primary; the compiler is not a gate (2026-08-13)

[`acceptance.md`](acceptance.md) T0 (dependency-tree walk) ranks above T1
(`dart compile wasm`), and a green T1 may not be cited as evidence of WASM-readiness
without T0's result beside it.

**Why.** Measured: `dart compile wasm` accepts `dart:io` and `dart:isolate` (§2.1). The
compiler is blind to the two libraries that dominate this port's surface.

---

## 2. Measured findings

All measured on **Dart SDK 3.12.0 (stable)**, Linux x64, 2026-08-13. These are
toolchain behaviours, not specification guarantees — re-measure on SDK upgrade. Method
and output in [`acceptance.md`](acceptance.md) §1.

### 2.1 dart2wasm accepts `dart:io` and `dart:isolate`

| Library | `dart compile wasm` |
|---|---|
| `dart:io` | compiles, exit 0 |
| `dart:isolate` | compiles, exit 0 |
| `dart:ffi` | rejected |
| `dart:html` | rejected |
| `dart:js` | rejected |
| `dart:mirrors` | rejected |

### 2.2 The `dart:io` stub throws on first use

The module from §2.1 was executed under Node 24.18.0 and threw
`Unsupported operation: _Namespace` at the first `File.existsSync()`. The failure mode
is exactly **compiles clean, throws at runtime**.

### 2.3 A runtime gate is available today without a browser

`dart test -p node -c dart2wasm` runs green, including an assertion that
`dart.library.io` is false. This makes [`acceptance.md`](acceptance.md) T2 a
zero-infrastructure CI addition, and it was the reason T2 could be specified as a gate
rather than as an aspiration.

`dart test -p chrome -c dart2wasm` compiles the module correctly but was **not observed
executing** — no Chrome binary in the development environment. T3 must be validated on
its first CI run.

---

## 3. Superseded positions

| Position in `plan.md` | Status |
|---|---|
| "No `dart:io`. The compiler hard-errors if any *reachable* code transitively imports it." (§1) | **False on Dart 3.12** — §2.1. Superseded by D-6. |
| "Isolates are experimental under dart2wasm" (§1) | Incomplete — `dart:isolate` compiles without complaint, so the compiler gives no signal either way. |
| "Use **conditional imports** … plus the injection seams" (§4, packaging strategy) | Superseded by D-1. |
| "One set of core packages … platform differences live behind conditional imports" (Goal 2) | Superseded by D-1 / D-5. The packages stay single-sourced; the mechanism changes. |
| "No regression on native. Every conditional seam keeps the existing native path byte-for-byte" (Goal 3) | Narrowed by D-3 to a behavioural commitment. |
| Gates A1/A2 (`dart compile wasm`) as the leading acceptance criteria | Demoted to T1 by D-6. |
| Tasks I4–I8 (the `at_auth` sweep) | Removed — owned by the PQ program's S-5/S-6. |

The predecessor `plan.md` is deleted rather than left in place, because its §1
constraint table and its A1/A2 gates are actively misleading. It remains in git history
at `33a062a61`; the material worth keeping — the persistence analysis, the `sqlite3`
compile validation, the storage-backend comparison, the B-series browser gates — is
carried into [`design.md`](design.md) and [`acceptance.md`](acceptance.md).

**Merge-time follow-up.** Four references to `docs/projects/wasm/plan.md` live on the
`at_client_sdk-atauth-wasm` branch and will dangle when both land —
`packages/at_auth/lib/at_auth_web.dart:23`, `packages/at_auth/CHANGELOG.md:51`,
`packages/at_auth/README.md:62`, and `packages/at_auth/test/wasm/dep_tree_test.dart:52`.
Repoint them at [`roadmap.md`](roadmap.md), or at
[`implementation-plan.md`](implementation-plan.md) for the `dep_tree_test.dart` case
(its comment refers to the task backlog).

---

## 4. Corrections to the predecessor doc

**`at_server_status`'s `dart:io` import is used, not unused.** `plan.md` §3.5 and task
I13 described it as an unused import and a one-line delete. In fact
`packages/at_server_status/lib/src/model/at_status.dart` uses `HttpStatus.found`,
`notFound`, `serviceUnavailable`, `internalServerError` and `ok` across eight call
sites in `_rootHttpStatus()` and `_serverHttpStatus()`. Deleting the import does not
compile. The fix is integer literals or a local constant class. The claim was wrong
when written — the file is unchanged since `33a062a61`.

Related and unlisted: `at_server_status` is on the client path via `at_auth`
(`at_auth_impl.dart:19`), and `at_auth_impl.dart:437` carries a second native default,
`atServerStatus ??= AtStatusImpl(...)`.

**`at_client_flutter` is not a platform implementer.** It implements exactly one
abstraction — `KeychainAtKeysIo extends WrittenAtKeysIo`
(`keychain_io_impl.dart:10`). All preference and path wiring lives in *app* code under
`example/` and `examples/`. It is a consumer.

**Inventory otherwise verified accurate** at HEAD `20f7f4da5`: the 21 `dart:io` files
across the six client-path packages (7/6/3/3/1/1), the 14 in excluded CLI packages, the
8 `dart:ffi` files all in at_chops, the single `dart:isolate` file, zero
`dart:html`/`dart:js`, and zero conditional imports in the main tree.

**Version staleness:** at_chops is 3.5.0 and at_lookup 3.6.1, both bumped since the doc
was written. Neither affects the analysis.

---

## 5. Open questions

**OQ-1 — Does `at_auth` ship a conditional default or a removed one?**
The `at_client_sdk-atauth-wasm` worktree prototypes a *conditional* default
(`at_auth_impl.dart:19-20`, `src/io/defaults_stub.dart` returning null on web), while
`../pq/design.md` §4 specifies a *removed* default requiring injection. The prototype's
stub returns null rather than throwing, so it does not violate D-2 — but it does
violate D-1. Since the PQ program owns `at_auth`, this project raises the
inconsistency rather than resolving it. Resolve with S-5 before it sets a precedent the
rest of the sweep copies.

**OQ-2 — Do the `_io` barrels ship in the same major as the interface change, or one
release ahead?** Shipping the barrel first lets consumers migrate their imports before
the default disappears, turning one hard break into two soft steps. Shipping together
is one release instead of two. Decide per package at execution time.

**OQ-3 — Where do platform capabilities hang: `AtClientPreference` or
`AtServiceFactory`?** `AtServiceFactory` (`at_client_manager.dart:265`) is the closer
analogue and already has real overrides; `AtClientPreference` is what callers already
touch and already carries `CryptoConfig` as precedent. See
[`design.md`](design.md) §4.

**OQ-4 — File transfer: change the API, or extract the component?** Either
`uploadFile`/`downloadFile`/`reuploadFiles` move to `(bytes, name)` or a stream
abstraction, or file transfer becomes a separate optional native-only `AtFileTransfer`.
The second is smaller; the first is the better API. See [`design.md`](design.md) §2.8.

**OQ-5 — Which VFS?** `IndexedDbFileSystem` (main thread, async flush) or OPFS (true
sync, needs a dedicated web worker). Sets `at_client_web`'s execution model. Decide on
a measurement.

**OQ-6 — What is the acceptable WASM payload budget?** Compiled `.wasm` +
`sqlite3.wasm` + JS glue. Informs whether the IndexedDB fallback is ever needed —
[`design.md`](design.md) §5, gate X2. Record the number before deciding.

**OQ-7 — Directory lookup from a browser.** `root.atsign.org:64` is a raw TLS socket.
The `proxy:` convention and the injectable `SecondaryAddressFinder` unblock
development, but a production browser client needs a WebSocket- or HTTPS-reachable
directory endpoint. Whose work is that, and does it belong in this project?

**OQ-8 — How far does the `AtConnection` break reach outside this repo?** In-repo
callers are enumerated in [`design.md`](design.md) §2.1. External `implements
AtConnection` users are unknown.

**OQ-9 — Does `package:hive` compile as a dead stub under dart2wasm?** Hive 2.x's
internal conditional imports *should* resolve to the no-op `stub` backend when both
`dart.library.html` and `dart.library.io` are false. It gates whether dropping the
direct `hive` dependency is required or merely tidy. Note that §2.1 makes this less
comfortable than it sounds: a stub that compiles is exactly what does not prove safety.

**Answered.** *Does `package:sqlite3`'s web entry point compile under dart2wasm?*
**Yes** — Dart 3.11.3, `sqlite3` 2.9.4, with a negative control that failed as
required. [`design.md`](design.md) §0.2. Runtime behaviour remains unproven and is
covered by T3.1 and X1.

---

## 6. Decision log

| Date | Entry |
|---|---|
| 2026-08-03 | Predecessor `plan.md` written against `33a062a61` by gkc. `package:sqlite3` web compile validated. |
| 2026-08-12 | `at_client_sdk-atauth-wasm` worktree prototypes the at_auth barrel split and the dependency-tree walk; its `dep_tree_test.dart` header records that dart2wasm does not reject `dart:io`. |
| 2026-08-13 | Measured and confirmed the dart2wasm library-acceptance matrix (§2.1), the runtime throw (§2.2), and the browser-free test gate (§2.3). |
| 2026-08-13 | **D-1..D-6 ruled.** Injection over conditional imports; no throwing stubs; breaking majors accepted; `at_client_web` the only new package; `_io` barrels for native; structural gate primary. |
| 2026-08-13 | Doc set split five ways on the `docs/projects/pq` convention; `plan.md` deleted. |
| 2026-08-13 | Corrected the `at_server_status` "unused import" claim and the `at_client_flutter` "platform implementer" framing (§4). |
| 2026-08-13 | Ceded `at_auth` to the PQ program's S-5/S-6; tasks I4–I8 removed from this backlog. |
