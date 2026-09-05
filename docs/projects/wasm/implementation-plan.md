# implementation-plan.md — Build sequence & task backlog

**Status:** working execution plan (prescriptive). Task status as of 2026-08-27,
against `trunk` at `9d9e5f7d7`.
**Scope:** the phase sequence and the task backlog for the implementation-neutral
`AtClient` work, across `at_client_sdk` and `at_server`'s
`at_persistence_secondary_server`.
**Lane:** this doc carries **sequencing, the backlog, dependency order and the publish
ladder — only**. For *how* each seam works see [`design.md`](design.md); for the gates
see [`acceptance.md`](acceptance.md); for the *why* see [`decisions.md`](decisions.md);
for the trajectory see [`roadmap.md`](roadmap.md); for the non-Dart consumer story see
[`js-api.md`](js-api.md).

## Table of contents

- [0. How to read this plan](#0-how-to-read-this-plan)
- [1. Dependency graph](#1-dependency-graph)
- [2. Phase 0 — the ratchet (R)](#2-phase-0--the-ratchet-r)
- [3. Phase 1 — cheap seams (S)](#3-phase-1--cheap-seams-s)
- [4. Phase 2 — transport (T)](#4-phase-2--transport-t)
- [5. Phase 3 — persistence (P)](#5-phase-3--persistence-p)
- [5a. Client storage bundle (X)](#5a-client-storage-bundle-x)
- [6. Phase 4 — the sweep (I) and crypto (C)](#6-phase-4--the-sweep-i-and-crypto-c)
- [7. Phase 5 — `at_client_web` (W)](#7-phase-5--at_client_web-w)
- [8. Phase 6 — the JS/TS facade (J)](#8-phase-6--the-jsts-facade-j)
- [9. Phase 7 — deferred (D)](#9-phase-7--deferred-d)
- [10. Publish ladder](#10-publish-ladder)
- [11. Dependencies on the PQ program](#11-dependencies-on-the-pq-program)

---

## 0. How to read this plan

Task ids are stable and referenced from the other docs. Each carries a goal, the
concrete files, and the gate it advances.

Two sequencing principles:

1. **The ratchet lands first.** Phase 0 is small and unglamorous, and everything else
   decays without it. Because dart2wasm does not reject `dart:io`
   ([`decisions.md`](decisions.md) §2.1), a package that is neutral today reverts
   silently the first time someone adds an import — with no build failure anywhere.
2. **Break once per package.** Each neutral package takes exactly one major. Group its
   breaking changes into that release rather than spreading them across the phases that
   happen to touch it.

---

## 1. Dependency graph

```
R1 R3 R4 (ratchet — R1/R4 landed, R3 unimplemented; R2 and R5 withdrawn)
  │
  ├──────────────┬───────────────┬──────────────┐
  ▼              ▼               ▼              ▼
S1..S6        T1..T8          P1..P5         C1..C4
(in review)   (transport)     (persistence)  (crypto verify)
  │                │               │              │
  │                ▼               ▼              │
  │           at_lookup 4.0.0   web SQLite        │
  │                │               │              │
  └────────────────┴───────┬───────┴──────────────┘
                           ▼
                    I1..I11 (sweep)
                           │
                           ▼
                    at_client 4.0.0 · at_utils 4.0.0
                           │
                           ▼
                     W1..W4 (at_client_web)
                           │
                           ▼
                        T4 gates
                           │
                           ▼
                    J1..J8 (JS/TS facade + npm)
                           │
                           ▼
                        T6 gates
```

T (transport), P (persistence) and C (crypto verification) are independent and run in
parallel. The sweep integrates them.

---

## 2. Phase 0 — the ratchet (R)

Advances [`acceptance.md`](acceptance.md) T0. No behaviour change; no break.

> **Status: landed, with two tasks withdrawn and one not done.**
> [#2149](https://github.com/atsign-foundation/at_client_sdk/pull/2149) (2026-08-24) and
> [#2183](https://github.com/atsign-foundation/at_client_sdk/pull/2183) (2026-08-27).
> The gate ships as `tools/wasm_shakedown` — a standalone CLI with its own suite, run by
> the `wasm_shakedown` and `wasm_ratchet` jobs, hard rather than allowed-to-fail. The
> gated set lives in `.github/wasm_gates.yaml` and holds **`at_chops` and `at_auth`
> only**: `at_utils`, `at_lookup` and `at_client` own 3, 6 and 7 offenders and are absent
> deliberately, so a declared gate means "web-safe" and not "here is the backlog". They
> join with Phases 2 and 4.

- **R1 — Generalise the dependency-tree walk. ✅ Done**, as
  `tools/wasm_shakedown`. Shipped as a standalone CLI rather than the shared *test*
  utility this task specified — the walk needed its own tests, and a gate that is itself
  untested is the thing it is supposed to prevent. It implements the web-resolution walk
  (`dart.library.io` false, `dart.library.js_interop` true), a one-way baseline per barrel
  (`allowed_offenders` + `max_blocked_packages`), a `min_files_walked` floor against a
  stalled walk, and mandatory `controls` that assert the walk still reaches what a barrel
  exists to quarantine. → T0.1, T0.2
- **R2 — No-conditionals gate. ⛔ Withdrawn.** at_auth 4.0.0-rc1 ships one deliberate
  conditional export with both branches real; the gate would have had to allow-list its
  only subject. Replaced by the audit requirement in
  [`acceptance.md`](acceptance.md) T0.3 — both branches of a conditional must be walked,
  the native one by a `control`, which resolves with io semantics. See
  [`decisions.md`](decisions.md) D-1 as amended, and OQ-1.
- **R3 — No-throwing-stub gate. ❌ Not done.** `wasm_shakedown` has no such key. D-2 is
  upheld by review only. Worth landing before Phase 4, where removing the native defaults
  makes a hand-written stub the tempting substitute — and a stub passes T0.1 cleanly. → T0.4
- **R4 — Wire R1–R3 into CI. ✅ Done** (R1 only, per the above). Two jobs in
  `.github/workflows/at_libraries.yaml`: `wasm_shakedown` for the tool's own tests, and
  `wasm_ratchet` for the gates, which `needs` it so a broken walk reports once rather than
  as a failure in every gated package.
- **R5 — Add the T2 matrix dimension. ⛔ Withdrawn.** Not a scheduling deferral: on the
  hosted runner every suite fails to load before any test body runs, so an
  allowed-to-fail job would never once have passed. Waits on a pinned Dart/Node pair —
  [`decisions.md`](decisions.md) §2.7, [`acceptance.md`](acceptance.md) §4. → T2

---

## 3. Phase 1 — cheap seams (S)

Preparation. Changes no public interface, breaks nothing, and shrinks every later diff.

> **Status: all six written, none merged.** Tracked as
> [#2158](https://github.com/atsign-foundation/at_client_sdk/issues/2158), open as a
> three-PR stack, each based on the one below it:
>
> | PR                                                                    | Base    | Tasks  | State                                                   |
> | --------------------------------------------------------------------- | ------- | ------ | ------------------------------------------------------- |
> | [#2162](https://github.com/atsign-foundation/at_client_sdk/pull/2162) | `trunk` | S4–S6  | Ready, checks green, review required                    |
> | [#2163](https://github.com/atsign-foundation/at_client_sdk/pull/2163) | #2162   | S1, S2 | **Draft.** `functional_tests_at_onboarding_cli` failing |
> | [#2164](https://github.com/atsign-foundation/at_client_sdk/pull/2164) | #2163   | S3     | **Draft. Conflicting.** `end2end_test_14` failing       |
>
> **The gate shrink is already demonstrated.** #2162 takes `dart:io` out of
> `at_server_status` and tightens at_auth's `max_blocked_packages` from 4 to 3 in the same
> PR — which is exactly the "T0 shrinks" the phase promises, and the first evidence that
> the one-way baseline is tightened when convenient rather than ignored.
>
> **Scope creep to resolve before merge.** #2163's tip commit moves at_client onto
> `at_lookup 3.7.0-rc1` and reworks `RemoteSecondary` around its constructor, which is
> more than S1 and S2 describe. Either it belongs to Phase 2, or S1's scope should be
> restated to include the uptake — but it should not merge as an unnamed rider on a phase
> whose whole premise is that it changes no interface.

- **S1 — Plumb the at_lookup socket factories.** ✅ Written, #2163 (draft).
  `at_client/lib/src/client/remote_secondary.dart:44-56` constructs `AtLookupImpl`
  without passing `secureSocketFactory`, `socketListenerFactory` or
  `outboundConnectionFactory`, all of which are constructor params at
  `at_lookup_impl.dart:108-131`. Pass them through. Also make the second, non-injectable
  `RemoteSecondary` construction at `at_client_impl.dart:1225` injectable.
- **S2 — Plumb `MonitorOutboundConnectionFactory`.** ✅ Written, #2163 (draft).
  `Monitor` accepts it at `monitor.dart:93`; `NotificationServiceImpl._` (`notification_service_impl.dart:76-84`)
  never passes it, and `create` does not expose it. Expose and pass.
- **S3 — Plumb the `AtSyncQueue` box seam.** ⛔ **Superseded by
  [D-12](decisions.md#d-12--client-storage-is-one-injected-bundle-and-it-owns-the-sync-queue-2026-09-05)**;
  written as #2164 (draft, conflicting) before the ruling. It plumbed
  `open({Box<String>? injectedBox})` through to `AtClientImpl.create` as the intermediate
  step toward backend-selectable storage. The queue no longer gets a route of its own: it
  belongs to the storage bundle (X-series below), which owns the keystore beside it. The
  injected-box seam stays as a test seam. **#2164 needs rework, not rebasing.**
- **S4 — Delete `sync_isolate_manager.dart`.** ✅ Written, #2162.
  `@Deprecated`, `// coverage:ignore-file`, zero references anywhere in `packages/`
  outside itself, and the only `dart:isolate`
  file in any `lib/`. Note T1 would never have flagged it.
- **S5 — Fix `at_server_status`.** ✅ Written, #2162.
  Replace `HttpStatus.found` / `notFound` / `serviceUnavailable` / `internalServerError` / `ok` in
  `at_server_status/lib/src/model/at_status.dart` (eight call sites in
  `_rootHttpStatus()` and `_serverHttpStatus()`) with integer literals or a local
  constant class, then drop the `dart:io` import. **Not the one-line delete the
  predecessor doc described** — [`decisions.md`](decisions.md) §4.
- **S6 — Move `dart_periphery` to `dev_dependencies:`** in at_chops. ✅ Written, #2162.
  FFI-based, used only under `example/`.

---

## 4. Phase 2 — transport (T)

The largest item, and the one breaking change with an unknown external blast radius.
Design in [`design.md`](design.md) §2.1.

- **T1 — Audit `implements AtConnection` and `getSocket()` callers.** In-repo:
  `remote_secondary.dart`, `monitor.dart`. External implementors are unknown
  ([`decisions.md`](decisions.md) OQ-8). **Do this before writing the interface** —
  enumerate the blast radius first.
- **T2 — Define `AtTransport`.** Inbound `Stream<List<int>>`, a sink,
  `connect()`/`close()`, connection metadata. No `dart:io` in its surface. Decide at
  this point whether it lives in `at_lookup` or a new `at_transport` package — defer
  until the interface is written; `at_lookup` is the default.
- **T3 — Remove `Socket getSocket()`** from `connection/at_connection.dart:10`; follow
  through in `base_connection.dart:10,14,50` (`late final Socket _socket`,
  `socket.destroy()`, `socket.remoteAddress`), `outbound_connection.dart` and
  `outbound_connection_impl.dart`.
- **T4 — Retype the three factories** at `at_lookup_impl.dart:740,749,756` from
  `SecureSocket` onto `AtTransport`. They are already injectable and already plumbed by
  S1; the return type is the whole blocker.
- **T5 — `at_lookup_io.dart`.** Native transport wrapping `SecureSocket`; absorb
  `src/util/secure_socket_util.dart` whole (certs, `SecurityContext`, TLS keylog) as
  native-only.
- **T6 — Follow the raw sockets.** `monitor_client.dart:63` and
  `at_client/lib/src/stream/stream_notification_handler.dart:27` both call
  `SecureSocket.connect` directly, bypassing `SecureSocketUtil`. They must route through
  the transport or move to `_io`.
- **T7 — Web `SecondaryAddressFinder`.** `cacheable_secondary_address_finder.dart:209,222`
  opens a raw TLS socket to `root.atsign.org:64`. Ship a web implementation using one of
  the two existing escape hatches — the abstract interface, or the `proxy:<host>`
  convention. The production answer is OQ-7.
- **T8 — Publish `at_lookup` 4.0.0.** → T0 green for at_lookup, T2.2

---

## 5. Phase 3 — persistence (P)

In `at_server`'s `at_persistence_secondary_server`. Independent of T; can run in
parallel. Design in [`design.md`](design.md) §0.2 and §5.

- **P1 — Decide the VFS** (`IndexedDbFileSystem` vs OPFS) on a measurement, and record
  it. Blocks P2's web path and sets `at_client_web`'s execution model. OQ-5.
- **P2 — Split `src/impl/sqlite/sqlite_database.dart`'s `open`.** Prerequisite and the
  bulk of the work: retype the `_db` field and `raw` getter from `Database` to
  `CommonDatabase`, and repoint the four stores from `package:sqlite3/sqlite3.dart` to
  `package:sqlite3/common.dart`. Only the `open` call needs to differ; store bodies are
  unchanged. Native keeps `DynamicLibrary.open` (the Linux `libsqlite3.so.0` soname
  workaround) and `Directory().createSync`; web opens via `package:sqlite3/wasm.dart`
  with the P1 VFS.
- **P3 — Gate the `File` uses** in `sqlite_at_commit_log.dart` (~line 185) and
  `sqlite_at_access_log.dart` (~line 104). Both are log stores that client bundles do
  not instantiate — confirm that, then gate rather than port.
- **P4 — Extend `SqlitePersistenceConfig`** with the web open parameters (database
  name, VFS choice) alongside the native `storagePath`.
- **P5 — Add `SqlitePersistenceConfig.clientDefaults(...)`** for the commit-log-free
  client bundle shape, mirroring `HivePersistenceConfig.clientDefaults`. → X1

**Note:** this phase is native-side `at_server` work that stands on its own merits. The
SQLite backend improvements benefit native and server deployments regardless of the
browser outcome.

---

## 5a. Client storage bundle (X)

`at_client`-side, and the successor to S3. Design in
[`design.md`](design.md#22-storage-bootstrap) §2.2 and §2.3; ruled in
[`decisions.md`](decisions.md#d-12--client-storage-is-one-injected-bundle-and-it-owns-the-sync-queue-2026-09-05)
D-12. Independent of the P series, which is `at_server`-side.

- **X1 — Close the resurrection holes.** Prerequisite for X4, and worth landing alone.
  `stop()` nulls `_syncService`, `_notificationService` and `_enrollmentService`; `start()`
  only clears `_isStopped`, and the getters throw `StateError` rather than rebuilding. Two
  paths hand back a stopped client: `AtClientImpl.create` on a cached stopped instance, and
  `AtClientManager.setCurrentAtSign`'s same-atSign short-circuit. Make a stopped client
  either rebuild or refuse.
- **X2 — Define `AtClientStorage`.** The neutral interface owning the keystore and the
  sync queue, with the claim/release semantics D-12 requires: the bundle refuses a second
  opener itself rather than `at_client` keeping a registry.
- **X3 — Three implementations.** Hive-backed (today's behaviour), SQLite-backed, and
  in-memory covering keystore *and* queue so nothing touches disk. → X5, and the SQLite one
  pairs with P5.
- **X4 — Inject it, and release it.** A new static factory on `AtClient` that builds *and*
  wires the services, taking a bundle; `stop()` releases the claim and closes what the
  bundle opened. Deprecate `AtClientPreference.hiveStoragePath` with a migration note.
  Depends on X1.
- **X5 — Move the functional pack onto an in-memory bundle per file.** The named consumer:
  `test_utils.dart` shares `test/hive/client/$atsign` across every file, so one file
  inherits the next's pending sync queue and the next client's scoped enrollment is refused
  `AT0009` pushing keys it did not write. Depends on X3.
- **X6 — Consumers.** `at_client_flutter` and `at_onboarding_cli` move onto the factory, so
  both are WASM-ready ahead of the next major. Whether they move in this major or the next
  is open.

**Deferred to the major:** deprecating `AtClientManager`. Its `AtSignChangeListener`
capability exists only because there is a global current atSign, and where that goes is
undecided, and the migration is large:

```bash
grep -rl 'AtClientManager' --include='*.dart' packages tests | wc -l
```

---

## 6. Phase 4 — the sweep (I) and crypto (C)

### I — the `dart:io` sweep

- **I1 — Split the `at_utils` barrel.** `at_utils.dart:4-5` exports
  `src/networking/pseudo_server_socket.dart` and `src/config/app_config.dart`, breaking
  every consumer. `PseudoServerSocket` is used by `at_server` for ALPN multiplexing —
  **split, do not delete.**
- **I2 — Split `at_utils/lib/src/logging/handlers.dart`.** `ConsoleLoggingHandler`
  (`print`) stays neutral; `FileLoggingHandler` (`:34-48`), `StdErrLoggingHandler`
  (`:53-59`) and `CLILoggingHandler` (`:71-97`) move to `at_utils_io.dart`. The
  `dart:io` import at `:1` is what currently poisons the whole logger.
- **I3 — `app_config.dart` into `at_utils_io.dart`,** or inject the config.
- **I4 — Publish `at_utils` 4.0.0.**
- **I5 — Connectivity.** Replace `internet_connection_checker` behind an injectable
  interface; `remote_secondary.dart:14,188,192` and
  `connectivity_listener.dart:3,44-50`. Both call sites are already `@Deprecated` —
  evaluate deleting before porting. Drop the dependency from `pubspec.yaml`.
- **I6 — File transfer off the reachable surface.** `at_client_spec.dart:653-679` names
  `List<File>` in `uploadFile` / `downloadFile` / `reuploadFiles`, and
  `at_client.dart:4` exports the spec. Resolve OQ-4, then pull
  `at_client_impl.dart:1214,1389-1394,1456-1482`,
  `encryption_service.dart:310-350`, `file_transfer_service.dart` and
  `stream_notification_handler.dart` along with it.
- **I7 — Inject an `http.Client` into `file_transfer_service.dart`** (`:14,31,40,50`,
  top-level `http.post`/`get` with no seam). Worth doing independently of I6 — it is
  also the only way to test that service.
- **I8 — Storage backend selectable from `AtClientPreference`.**
  `storage_manager.dart:16` hardcodes `HiveAtPersistenceFactory()` and requires
  `hiveStoragePath`. Introduce the backend choice (`AtPersistenceBackendId` already has
  `hive` and `sqlite`) and an opaque storage location. Remove the unused
  `keyStoreSecret` parameter while in the file. Resolve OQ-3 here.
- **I9 — Backend-neutral `AtSyncQueue`.** Replace the direct `Hive.openBox` at
  `at_sync_queue.dart:121` with a small spec interface plus Hive and SQLite
  implementations, building on S3's plumbing.
- **I10 — Drop the direct `hive: ^2.2.3` dependency** from `at_client`'s pubspec once
  I8 and I9 land. OQ-9 determines whether this is required or merely tidy.
- **I11 — Publish `at_client` 4.0.0.** → T0 green, T1, T2.4

### C — crypto verification

Now verified **by execution** under T2.3 rather than by compile.

- **C1 — `cryptography`** must resolve to its pure-Dart implementation; its 2.x browser
  path uses Web Crypto via `dart:html`, which dart2wasm rejects. Critical path — it
  backs X-Wing, X25519, AES-GCM, the X25519 key pair, Argon2id and `at_chops_util`.
- **C2 — `pqcrypto: ^0.3.0`.** Backs `ml_kem_768_pure_dart.dart` and
  `ml_dsa_65_pure_dart.dart` — the algorithms a WASM build must use. Note
  `ml_kem_768_pure_dart.dart` imports `package:pqcrypto/src/…` for `KyberLevel`, a
  private-path import that can break on any upstream release.
- **C3 — `better_cryptography`.** Backs `aes.dart`, `aes_ctr_factory.dart`,
  `ed25519.dart`, `at_chops_util.dart`. A `cryptography` fork with unknown WASM status.
- **C4 — Measure Argon2id in pure Dart under WASM.** The number is the deferred UX
  input for `.atKeys` passphrase decryption. → X3

---

## 7. Phase 5 — `at_client_web` (W)

- **W1 — New package.** WebSocket transport against `wss://<host>:<port>/ws`, the web
  SQLite storage backend, a web `WrittenAtKeysIo` subtype, web connectivity, console
  logging.
- **W2 — Browser test harness** for the T3 and T4 gates: a page that loads the module
  and drives a virtualenv atServer. First run must confirm
  `dart test -p chrome -c dart2wasm` executes at all — unverified locally
  ([`decisions.md`](decisions.md) §2.3).
- **W3 — First live browser session.** → T4.1, T4.2
- **W4 — Payload measurement.** Compiled output + `sqlite3.wasm` + JS glue, gzipped and
  Brotli, for **both** compile targets. Record **before** revisiting the IndexedDB
  question. → X2

---

## 8. Phase 6 — the JS/TS facade (J)

Design in [`js-api.md`](js-api.md) and [`plans/wasm/api-designing.md`](../../../plans/wasm/api-designing.md)
(the Dart-side Layer A/B/C split); rulings D-7..D-11 in [`decisions.md`](decisions.md).
Builds on W1. Adds no Dart package — everything lands inside `at_client_web`.

**Rewritten 2026-08-18 for the collections pivot (D-10, D-11).** J1 previously described
a flat ~25-method surface; that surface is removed, not extended. `AtCollection<T>`
(`packages/at_client/lib/src/collections/collections.dart`) is now the sole facade target.

- **J1 — Layer B, the collections-shaped facade.** `packages/at_client_web/lib/at_easy.dart`
  (pure Dart, zero interop imports — `api-designing.md` §2.3): `AtEasy.collection<T>()`,
  `AtEasyCollection<T>` (`create`/`update`/`share`/`remove`/`where`/`watch`), `AtEasyItem<T>`
  (`data`, not `obj` — the ergonomic fix), `AtEasyQuery<T>`. `where(path, op, value)` builds
  the `PathField`/`Predicate` AST internally — `Predicate` is not serializable upstream
  (private `CmpPredicate._`, closure `PathField.extract`), so this bridge is Layer B's job,
  never Layer C's. Namespace auto-qualification and `expiration` defaulting live here too.
  → T6.3
- **J1a — The declared-`typeTag` registry (D-11).** Layer B tracks `(name, type)` →
  collection, enforcing the tag as mandatory at `collection()` call time. Ships with
  write-compatibility documented as open (JS-7): every JS-written record stamps `'n/a'` on
  the wire until route A (upstream `writeTypeTag`) or route B (a bounded carrier-class
  shim, verified viable via `CItem.toJson()`/`jsonEncode`) lands. Do not silently attempt
  route B without a decision recorded in `decisions.md` — it has a real ceiling.
- **J1b — Verify `subCollection`'s `fromJson`/`typeTag` XOR check.** `js-api.md` §5.4
  measured the omit-both escape (F1) only for the root `AtClient.collection()`; confirm
  `subCollection` behaves identically before binding it.
- **J2 — Error mapping.** Catch on the Dart side and rethrow a structured `AtError` with
  a stable `code`. The default boxed rejection must never reach a consumer.
  **`CollectionOpException`/`OpResult`/`OpFailure` fold into this same model** — a batch
  partial-failure surfaces as one `AtError`, never a second thrown/returned shape
  (`js-api.md` §6). → T6.4
- **J3 — Event surfaces.** `subscribe(cb) → unsubscribe` for notifications and all eight
  `AtCollection` stream-returning members; `Stream` has no JS bridge. **`CEvent` is not
  sealed upstream (`:5077`)** — the encoder must map an unknown subtype to a generic
  `'unknown'` event, never drop it or throw. → T6.5
- **J4 — The TS-supplied `KeyStore` seam.** Adapt a JS object behind the Dart storage
  interface, so Node consumers supply storage without a Dart package. Owned jointly with
  [`plans/wasm/key-storage.md`](../../../plans/wasm/key-storage.md). → T6.6
- **J5 — Entry point.** `packages/at_client_web/web/at_client_js.dart` — the `main()`
  that installs the facade on the global scope. Compiled with `dart compile js`; keep the
  dart2wasm build green in CI to preserve the option.
- **J6 — npm package.** `packages/at_client_web/npm/` — `package.json` **generated**, not
  hand-committed (verified dart-sass practice, `js-api.md` §8); `index.js` sets
  `globalThis.self` before load (or every Promise hangs on Node) **and wraps the raw
  `@JSExport` object in a real ES class** (private constructor, static `create()`) so
  `instanceof`/`new` behave correctly — `@JSExport` gives instance members only, no
  prototype chain. `index.d.ts` stays hand-written (documentation value; dart-sass
  precedent). Ship the `.js.map`.
- **J7 — T6 harness**, timeout-bounded throughout, plus a sample TS consumer that
  `tsc --noEmit` type-checks against the published typings. Extend T6.3 to cover
  `CItem`/`CEvent`/`Predicate` (not just `Future`/`Stream`/`List`/`Uint8List`), and add a
  gate asserting a JS-written record carries its declared `typeTag` correctly once J1a's
  route is chosen. → T6.1, T6.2, T6.7
- **J8 — Resolve JS-1**: measure which implementation `cryptography` selects under
  dart2js and whether Web Crypto removes the deferred Argon2id work
  ([`design.md`](design.md) §2.10).
- **J9 — Resolve JS-7**: raise the additive `writeTypeTag` change upstream; fall back to
  J1a's carrier-class shim only if declined.
- **J10 — Resolve JS-8**: ship the `AtClientManager` singleton documented as one atSign
  per page/process, plus a Layer B `AtFailure.alreadyInitialised` on a second distinct
  atSign (~10 lines) — converts silent state corruption into a clear error.

---

## 9. Phase 7 — deferred (D)

- **D1 — File-transfer web implementation** via `package:web` File/Blob.
- **D2 — Browser onboarding and key-import UX.** The `.atKeys` *file* does not exist in
  a browser; the flow needs paste, upload or QR feeding bytes into the existing decode
  path.
- **D3 — Argon2id performance work,** driven by C4.
- **D4 — Raw IndexedDB backend,** only if W4's payload measurement rules `sqlite3.wasm`
  out.
- **D5 — `at_client_cli` and `at_client_flutter` as true platform implementers.**
  Deferred under [`decisions.md`](decisions.md) D-4; the `_io` barrels serve until then.
- **D6 — A `Clock` / `RandomSource` seam.** Portable under WASM, so not a port
  requirement — but a real testability win. Deliberately excluded here;
  [`design.md`](design.md) §2.11.

---

## 10. Publish ladder

Dependency order, one major per package:

| # | Package            | Version   | Phase    | Break                                                                                                             |
| - | ------------------ | --------- | -------- | ----------------------------------------------------------------------------------------------------------------- |
| 1 | `at_chops`         | minor     | C, S6    | none — dependency move only. **3.6.1 on trunk; S6 pending in #2162**                                              |
| 2 | `at_auth`          | **4.0.0** | *PQ S-5* | `FileAtKeysIo` → `at_auth_io.dart`; default removed; registrar → `package:http`. **✅ 4.0.0-rc1 on trunk (#2179)** |
| 3 | `at_utils`         | **4.0.0** | I1–I4    | barrel split; native handlers → `at_utils_io.dart`                                                                |
| 4 | `at_lookup`        | **4.0.0** | T        | `Socket getSocket()` removed; factories retyped. **3.7.0-rc1 on trunk**                                           |
| 5 | `at_server_status` | minor     | S5       | none — `HttpStatus` → literals. **1.1.2-rc1 on trunk; S5 pending in #2162**                                       |
| 6 | `at_client`        | **4.0.0** | I        | `File` off the spec; storage backend selectable; connectivity injected                                            |
| 7 | `at_client_web`    | 1.0.0     | W        | new                                                                                                               |
| 8 | consumers          | —         | —        | `at_onboarding_cli`, `at_cli_commons`, `at_client_flutter`, both test packages                                    |

**Coordinate step 8 with the PQ program's S-6**, which bumps the same consumers for
`at_auth ^4.0.0`. Doing them separately means two breaking sweeps through the same
files.

---

## 11. Dependencies on the PQ program

| This project needs                                                                                                                                                  | From                                                                                | Status                                                                                                                                                       |
| ------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `at_auth.dart` free of `dart:io`; `FileAtKeysIo` in `at_auth_io.dart`; the `atKeysIo ??=` default removed; registrar on `package:http`; `_defaultProbeSocket` moved | **PQ S-5** ([`../pq/implementation-plan.md`](../pq/implementation-plan.md):312-326) | **✅ Landed** — 4.0.0-rc1, [#2179](https://github.com/atsign-foundation/at_client_sdk/pull/2179), 2026-08-25. `at_auth` is gated in `.github/wasm_gates.yaml` |
| Consumer bumps onto `at_auth ^4.0.0`                                                                                                                                | **PQ S-6** (:328-339)                                                               | Follows S-5. Still to come; coordinate with ladder step 8                                                                                                    |
| A ruling on conditional-default vs removed-default in at_auth                                                                                                       | OQ-1                                                                                | **✅ Resolved** 2026-08-27 — removed default *and* one conditional probe. [`decisions.md`](decisions.md) D-1, OQ-1                                            |

This project does **not** touch `at_auth`. The predecessor doc's tasks I4–I8 are
removed for that reason ([`decisions.md`](decisions.md) §3). If S-5 slips, the sweep
proceeds without it — `at_auth` simply remains a blocked package in R1's ratchet until
it lands. It landed, so this contingency is spent: `at_auth` is now a gated package, and
its four remaining blocked packages (`at_lookup`, `at_utils`, `chalkdart`,
`at_server_status`) are all inherited and come off as each is ported.
