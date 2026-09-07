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
  `remote_secondary.dart` — and only that one now. ⚠️ This row said
  `monitor.dart` too; `Monitor` gave up its socket in X6 and calls `getSocket`
  zero times. External implementors are unknown
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
- **T4 — Retype the three factories** — `AtLookupSecureSocketFactory`,
  `AtLookupSecureSocketListenerFactory`, `AtLookupOutboundConnectionFactory`, at
  `at_lookup_impl.dart:1312,1323,1332` (this row cited `:740,749,756`, which is stale) —
  from `SecureSocket` onto `AtTransport`. They are already injectable and already plumbed
  by S1; the return type is the whole blocker.
  ⚠️ **`AtLookupImpl`'s `dart:io` binding is five occurrences, not a rewrite** (measured
  2026-09-06): those three factory classes, which are the io implementations co-located at
  the foot of the file, plus `createOutBoundConnection` at `:834`, whose local is typed
  `SecureSocket` and which catches `SocketException` — io-typed only because the factory's
  return type is. Retype the three, move their bodies to `_io`, and the core is io-free
  with no logic change. `at_lookup.dart`, where `withSecureSocket` lives, imports no
  `dart:io` at all today.
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
- **T9 — Let the APP inject the transport, and thread it to every construction site**
  (gkc, 2026-09-06). This is the structural gap the rest of phase T does not close:
  retyping the factories makes a web transport *possible*, but nothing lets an app
  *supply* one. `at_client_web` needs every `AtLookUp` its process builds to sit on a
  WebSocket, so the transport joins [`AtClientStorage`](#5a-client-storage-bundle-x) and
  `AtKeysIo` as a thing the app hands in.
  **Six production sites hardcode `secureSocketTransport(...)`, in three packages**
  (measured 2026-09-06): at_client `client/remote_secondary.dart:150` and
  `service/notification_service_impl.dart:92` — the only two files in at_client importing
  `at_lookup_io.dart`, and the sync service inherits the first through its own
  `RemoteSecondary`; at_auth `at_auth_impl.dart:151` and `:259` and
  `enroll/enrollment_handshake.dart:61`; at_server_status `at_status_impl.dart:115`.
  ⚠️ **at_auth is not optional here.** A web app authenticates *before* it has an
  `AtClient`, so an injection that reaches only at_client still drags `dart:io` through
  onboarding, `authenticate` and the enrollment handshake. The transport is an
  ecosystem-level injection, not an at_client parameter.
  ⚠️ **The factory is nearer neutral than "not yet built":** `withSecureSocket` already
  takes an `AtLookupTransport`, so what is missing is a neutral NAME and an io-free
  `AtLookupImpl` for it to construct (T4). Its own dartdoc anticipates the sibling:
  "Named for its transport, so a differently-transported factory can join it later rather
  than this one growing a mode flag."
  **Open: where the injected transport lives.** `AtClientPreference` is the wrong home —
  it is a data bag, the transport is a live object carrying three factories, and
  `setPreferences` would make it swappable mid-life. Reading it off `AtClient` matches
  `atKeysIo` exactly and reaches `NotificationServiceImpl` and `SyncServiceImpl`, which
  build their own connections; a shared platform bundle carrying transport + storage +
  keysIo is the other shape. Not settled.

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
- **P5 — ~~Add~~ `SqlitePersistenceConfig.clientDefaults(...)`** — **already published**:
  `at_persistence_secondary_server` 5.2.1 carries it (`sqlite_persistence_config.dart`),
  mirroring `HivePersistenceConfig.clientDefaults`. Nothing to add; X3's SQLite bundle
  consumes it. → X3

**Note:** this phase is native-side `at_server` work that stands on its own merits. The
SQLite backend improvements benefit native and server deployments regardless of the
browser outcome.

---

## 5a. Client storage bundle (X)

`at_client`-side, and the successor to S3. Design in
[`design.md`](design.md#22-storage-bootstrap) §2.2 and §2.3; ruled in
[`decisions.md`](decisions.md#d-12--client-storage-is-one-injected-bundle-and-it-owns-the-sync-queue-2026-09-05)
D-12. Independent of the P series, which is `at_server`-side.

- **X1 — Pin the stopped-client guard.** ✅ Merged, #2203. Prerequisite for X4, and worth landing alone.
  `stop()` nulls `_syncService`, `_notificationService` and `_enrollmentService`; `start()`
  only clears `_isStopped`, and the getters throw `StateError` rather than rebuilding — so
  a stopped client must never be handed back. It already is not: the same-atSign
  short-circuit in `AtClientManager.setCurrentAtSign` carries `isStopped == false`, and
  nothing outside the manager calls `AtClientImpl.create` in production. What was missing
  is the test. `crypto_provider_reconcile_test.dart` pins the short-circuit's crypto
  adoption and never stops the client, so the clause could be deleted with nothing going
  red. `at_client_manager_stopped_client_test.dart` pins it; deleting the clause reddens
  it, quoting its reason. (First written as two open holes; one was already guarded and the
  other has no caller.)
- **X2 — Define `AtClientStorage`.** ✅ Merged, #2204. The neutral interface owning the keystore and the
  sync queue, with the claim/release semantics D-12 requires: the bundle refuses a second
  opener itself rather than `at_client` keeping a registry. Ships with the Hive-backed
  implementation wired in as the default, so it is exercised rather than declared. The
  per-object claim only: the Hive backend's per-atSign guard waits for X4, because nothing
  releases storage before then and the guard would refuse every same-atSign rebuild.
- **X3 — Three implementations.** ✅ Merged, #2205, and merged back into the spike at
  `51bdb6230`. Hive-backed (today's behaviour), SQLite-backed, and
  in-memory covering keystore *and* queue so nothing touches disk. The in-memory one **is**
  `SqliteAtClientStorage` on `:memory:`, and both SQLite-backed classes are exported only from
  `package:at_client/sqlite.dart`, so X5's pack imports that barrel. → X5, and the SQLite one
  pairs with P5.
- **X4 — Inject it, and release it.** A new static factory on `AtClient` that builds *and*
  wires the services, taking a bundle; `stop()` releases the claim and closes what the
  bundle opened. Deprecate `AtClientPreference.hiveStoragePath` with a migration note.
  Depends on X1.
  ⚠️ **What #2208 actually shipped is narrower than this sentence.** It added `storage:` to
  the doors that already existed (`AtClientImpl.create`, `setCurrentAtSign`, and via X5
  `fromAuthSession`) and the release semantics, and left the static factory and the
  deprecation unbuilt. Both landed in X6 instead, the deprecation only once
  `AtClientStorage.closedByClient` made a bundle able to be closed by the client. **Measured 2026-09-05 on trunk `d13516d95` (the X3 merge), storage-release
  semantics built and run against the packs before landing anything:** 69 tests red across three causes —
  (a) 38 fixtures that rebuild a client for one atSign without stopping the previous one,
  which the per-atSign Hive guard now refuses; (b) a sync round outliving `stop()` and
  touching closed storage (`processSyncRequests → syncQueueSyncSnapshot → size`), fixed
  first and separately as *a stopped sync service abandons its round* (#2206); (c) **the e2e pack
  depends on cached-client resurrection for key material** — `getAtClient()` calls
  `setCurrentAtSign` with no `atKeysIo`/`atChops`, and its own comment says so; a fresh
  client on switch-back rebuilt `AtChops` from its keystore and 14 tests died with
  `PKAM Keypair required for signing`. Why the reopened keystore lacked the keys is NOT
  established. And trunk's `AtClient.stop()` dartdoc *promises* resurrection: "Local
  storage is NOT closed. The instance remains in the internal cache and reuses its
  still-open local keystore when resumed". X4's storage release therefore changes a
  documented contract, and the packs (X5) and that dartdoc move with it. ⚠️ **This said the
  storage-release work was parked as a git stash named `x4-release-wip` until 2026-09-06.**
  It is not: it is [#2208](https://github.com/atsign-foundation/at_client_sdk/pull/2208) on
  branch `gkc-at-client-storage-release`, which X5 is stacked on. Resume by checking that
  branch out, never from a stash.
- **X5 — Each functional test file gets its own storage, on a selectable backend.**
  ✅ **Built 2026-09-06.** The consumer was real: `test_utils.dart` gave every file
  `test/hive/client/$atsign`, the runner clears that directory once per run and never
  between files, and CI never clears it at all. Each file now names itself
  (`TestUtils.isolateStorage('<file>')`) and gets one bundle per atSign, at a location no
  other file opens.
  **Which backend is built comes from `AT_FUNCTIONAL_STORAGE`** (gkc, 2026-09-06):
  `hive` by default — what the pack has always run on, so the default run's behaviour is
  unchanged — or `sqlite` or `memory`. An unrecognised value is refused rather than
  defaulted, so a typo cannot quietly run the backend it was meant to replace. A second CI
  job, `functional_tests_storage`, runs the same pack again on the other two, beta channel
  only; the existing job's matrix is untouched, so nothing is renamed.
  **Measured against `at_virtual_env:local`, 82 tests each: hive 82, sqlite 82, memory 82,
  all passing.** That is the first time either SQLite-backed bundle has carried a live put,
  get, sync drain or notification rather than only the unit contract tests. ✅ **CI agrees:
  on [#2210](https://github.com/atsign-foundation/at_client_sdk/pull/2210) both new jobs
  passed first time, and the run is 11 of 11 green** — `end2end_test_14` needed one re-run
  for `bypasscache_test`, the intermittent that has its own row and fails pre-X4a. Re-derive
  rather than quoting: `gh run list --branch gkc-x5-functional-storage`.
  ⚠️ **"A bundle per file" was not buildable as written.** A bundle is bound to one atSign
  at construction and several files drive two, so the unit is per *(file, atSign)*. Three
  things the build found, none of them visible by reading:
  - **The claim guard caught nine tests sharing one atSign's store across principals.**
    `enrollment_test` re-authenticates as its own enrolment and reads what the owner wrote
    locally, so it hands the store over explicitly at the five points where it stops every
    client. The guard firing is the evidence that the sharing was real and unnoticed.
  - **A child isolate is a separate heap**, so `sync_multiple_client_test`'s two clients
    cannot be handed a bundle at all — that isolate builds its own from the path string it
    is sent. The third client in that file sets `isLocalStoreRequired` false and opens no
    local store.
  - **`setCurrentAtSign` treated any storage argument as a change** and took the
    destructive stop/recreate path, which would have altered the client lifecycle at every
    site the pack touches. Re-offering the bundle a client already holds is now not a
    change; a different bundle still rebuilds.
  Two `at_client` changes ride with it: `fromAuthSession` accepts a `storage` bundle, being
  the one door that could not take one; and `commitLogPath` came off the pack's preferences,
  it being read nowhere in `at_client`. A preference now carries no storage path at all, so
  a call site that forgets a bundle fails loudly instead of opening the shared directory.
  ⚠️ **Owed, found while scoping and not fixed:** `InMemoryAtClientStorage` distinguishes
  instances by `identityHashCode`, which is a hash and not an identity, so two live
  in-memory storages whose hashes collided would be refused as one store. Negligible at the
  handful per test process this pack opens; wrong in principle.
  Depends on X3.
- **X6 — Consumers.** ✅ **Merged to trunk 2026-09-07** as
  [#2211](https://github.com/atsign-foundation/at_client_sdk/pull/2211), 50 of 50 checks green,
  merge commit `a7ad4a545` — a merge commit rather than a squash, so the branch's own history is
  on trunk (#2210 next door was squashed, which is why `git cherry` shows its commits as absent).
  Built 2026-09-06 on `gkc-x6-consumers`, which GitHub deleted on merge. It **targeted trunk
  directly**, having been stacked on
  [#2210](https://github.com/atsign-foundation/at_client_sdk/pull/2210) until that merged and was
  retargeted. ⚠️ This row said "stacked" until 2026-09-07, and that
  word carries a consequence: a stacked PR gets no real CI, so it would have a reader discount
  #2211's checks. They were real. **Ruled: they move
  in THIS major** (gkc, 2026-09-06), and `buildAtClient` (then `AtClient.create`) has nothing to do with
  `AtClientManager` — future apps, once the manager is gone, manage their clients'
  lifecycles explicitly, so the job now is to make that *possible* while apps using the
  manager see no change.
  ⚠️ **The row's premise was wrong in both directions.** `at_client_flutter`'s `lib/` had
  nothing to move: zero references to `AtClientPreference`, `AtClientImpl` or
  `AtClientStorage`; it wraps `AtAuth` and reads `AtClientManager.getInstance().atClient`,
  and only its example apps set storage paths. Meanwhile `at_cli_commons`, which the row
  never named, was one of only three production `lib/` sites setting `hiveStoragePath` —
  though it reaches the client through `AtOnboardingServiceImpl`, so there is one seam, not
  two.
  **What landed.** `buildAtClient` (then `AtClient.create`) — X4's promised static factory, never built by #2208,
  which added `storage:` to the existing doors instead. It builds a client and wires its
  three services, taking `storage` alongside `atKeysIo`, registers nothing, and refuses an
  atSign whose client is already live rather than handing back one the caller does not own.
  `AtOnboardingPreference.storage` carries a bundle through to `setCurrentAtSign`;
  `at_cli_commons` needed no change, because `CLIBase` already passes the caller's own
  preference object through untouched. `AuthService.createClient` turns a completed
  authentication into a client the app owns, and `FlutterEnrollmentService` takes an
  optional client so it can work against one.
  **`AtClientStorage.closedByClient`** (gkc's idea, 2026-09-06) moves lifetime ownership onto
  the bundle instead of inferring it from how the storage arrived. That removed the last
  argument for `hiveStoragePath`, which is now deprecated along with `commitLogPath` — the
  latter read by nothing anywhere, so every caller setting it was setting a value with no
  effect.
  ⚠️ **`AtServiceFactory` cannot go manager-free in 3.x**: every method takes an
  `AtClientManager` positionally and non-nullably, and relaxing that makes the three
  existing `ServiceFactoryWithNoOpSyncService` overrides illegal. `buildAtClient` (then `AtClient.create`) takes
  per-service builder callbacks instead, which covers the only override anyone uses.
  ⚠️ **Owed.** `at_onboarding_cli` and `at_cli_commons` still set `hiveStoragePath` as their
  default (eleven analyzer infos); moving them onto client-closed bundles changes when the
  client's store closes, so it wants the live packs rather than riding in on unit
  green. Eleven example apps in the other widget packages still set `commitLogPath`, each
  needing its own version decision. **X6 changes storage ownership semantics, so the live
  packs were owed before its PR was ready — all FOUR of them, not three. The fourth is
  the onboarding-CLI **proxy** pack, which cannot run on this Mac at all (see the X6 review
  notes below), so on this machine "all four" meant three run locally plus one delegated to CI.
  That is what happened, and #2211 merged with 50 of 50 checks green.**
  Depends on X4.

  **Adversarial review of [#2211](https://github.com/atsign-foundation/at_client_sdk/pull/2211),
  2026-09-06** (13 agents, six dimensions, every finding attacked by a skeptic). Five
  high-severity defects were confirmed in source and **fixed on the branch** at `100e73b9d`:
  a permanently deaf notification listener after one failed first connect; two documented
  preferences (`monitorHeartbeatInterval`, `monitorHeartbeatResponseTimeout`) gone dead with
  the effective interval halved 59s → 30s; `at_onboarding_cli`'s and `at_cli_commons`' floors
  unable to supply what their `lib/` now calls; and `buildAtClient` (then `AtClient.create`)'s dartdoc asserting the
  opposite of what the code does.
  ⚠️ **The retry for the first defect belongs in at_client, NOT at_lookup.**
  `startNotifications` deliberately *surfaces* a failed start — three at_lookup tests pin
  that, one reasoning "failing loudly beats a connection that silently never receives
  anything". Fixing it in at_lookup reddened all three; `Monitor` retries instead.
  ⚠️ **One of the six author claims was FALSE: "deleting monitor_test.dart's 13 tests is
  safe".** Eleven are covered by at_lookup's 26 muxable tests; **two are not** — the heartbeat
  *cadence* tests, which set the preference and asserted the resulting interval, where
  at_lookup's replacements set `AtLookupImpl.heartbeatInterval` directly and cannot see an
  `AtClientPreference` at all. They were unportable while the wiring was missing; **the fix at
  `100e73b9d` restores that wiring, so porting them is now possible and owed.**
  **The rest of that list was worked 2026-09-06 and is now DONE**, each fix pinned by a test
  whose break-it mutation reddens the assertion and quotes its own reason string:
  - **A half-built client is no longer filed and handed out.** `buildAtClient` (then `AtClient.create`) wraps its
    service wiring in `try { … } catch (_) { await client.stop(); rethrow; }`, which unfiles
    the client and releases its claim on the storage location.
  - **The four unconditional "borrowed" dartdocs** are corrected, plus two in the functional
    pack that stated the rule as a general claim about clients and four more in the
    CHANGELOGs.
  - **Notification handling is serialised again.** `Monitor._onNotification` pauses the
    subscription for the duration of the handler, exactly as the socket-owning Monitor did.
    ⚠️ **The "back-pressure seam is unreachable" half of this row was WRONG.** The seam is
    explicit on `AtLookupMuxable.notifications`, wired to `pauseDelivery()` and pinned by
    at_lookup's own tests — at_client simply never reached it. One pause fixes both halves.
  ⛔ **THREE connections to the atServer is the default, and stays** (gkc, 2026-09-06): the
  verb processor, the monitor, and the sync service. That has been at_client's behaviour all
  along and nothing here changes it — `AtClientImpl._init` builds the first through
  `buildRemoteSecondary`, `NotificationServiceImpl` hands `Monitor` a FRESH lookup, and
  `SyncServiceImpl.create` builds its own `RemoteSecondary`. The `monitor:` and
  `remoteSecondary:` injection points are test-only; at_auth's `reuse: true` supplies the verb
  connection rather than adding a fourth, so the count is three either way.
  ⚠️ **Nothing pins this**, and `Monitor`'s dartdoc still offers the collapse to two ("or the
  one `RemoteSecondary` already holds"). It carries two reasons against — no atServer
  implements `monitor:multiplexed`, and `_onNotification` pauses the connection while a
  handler runs, which on a shared socket would deadlock the handler's own put — but it reads
  as an option rather than a ruling. A test asserting the three lookups are distinct instances
  would need a `@visibleForTesting` getter for sync's, which is private. Owed, not done.
  ⚠️ **Sync's promptness rides on the MONITOR connection, not its own.**
  `statsServiceListener` subscribes to `statsNotification` through the notification service
  and enqueues a system sync on each one; its own connection carries only `sync:`, `batch:`
  and `stats:3`. So a monitor that goes silently deaf costs sync its trigger and drops it to
  the 30-second `_periodicSyncInterval` safety net — which is what the watchdog above now
  catches.
  - **The socket-alive-but-silent watchdog is back**, as `AtClientPreference.
    monitorSilenceTimeout` (default 60s, `Duration.zero` off) driving a timer in `Monitor`
    that rebuilds through `stopNotifications`/`startNotifications`.
    ⚠️ **Ruled: at_client, not at_lookup** (gkc, 2026-09-06). The argument for putting it in
    at_lookup mis-cited `at_lookup_impl.dart:914-922`, which argues against Monitor owning
    the reconnect BACKOFF and is conditioned on "a connection that also carries verb
    traffic" — Monitor's is dedicated. This PR changes at_lookup by zero lines and at_lookup
    is ahead of at_client on the release train.
    **It has a live test as well as three unit tests**, and it needed no test hook: the
    atServer writes a stats notification to every monitor connection every 15s by default
    (`at_secondary_config.dart:63` on at_server `origin/trunk`), which is a real clock to
    bracket the budget around. `tests/at_functional_test/test/monitor_silence_test.dart`
    runs two 45-second arms differing only in the budget — 3s must rebuild, 40s must not —
    observed through the public `currentListenerStateStream`, with the stats-arrive premise
    asserted first so a server that stopped sending them fails as itself. ⚠️ What no test
    here does is wedge a real atServer into answering heartbeats while delivering nothing;
    the arms reproduce the condition the watchdog keys on, not the fault that causes it.
  - **The Flutter app-owned path works end to end.** `EnrollmentRequestList` takes an
    optional `enrollmentService` and every client read goes through it.
    ⚠️ **It was six reaches, not five, and the sixth fires first**: the service's constructor
    wires `onListen` to a method whose first statement touches `atClient`, which runs
    synchronously inside the widget's own `.listen`. Swapping only the five named sites would
    not have fixed it. The widget now disposes only a service it built itself.
  - **`at_onboarding_cli` is 1.17.0-rc1** (gkc, 2026-09-06), and `at_cli_commons` floors it
    there — it had pinned `^1.16.1-rc2`, which resolves a version without `storagePath`.
  - **`dart analyze --fatal-infos`**: ⚠️ **that row's diagnosis was WRONG.** None of the 143
    same-package uses of the two deprecated fields produces a diagnostic, because
    `deprecated_member_use_from_same_package` is not in `package:lints/recommended.yaml`,
    which is all this package includes. The 289 infos were 286 pre-existing
    `deprecated_member_use` from at_chops/at_auth plus 3 `unnecessary_import` this PR did
    add; those three are removed. `--fatal-infos` is not a CI gate — CI runs bare
    `dart analyze` and `flutter analyze --no-fatal-infos`.
  **Raised while building X6, tracked nowhere else:**
  - **The monitor connection advertises nothing.** `RemoteSecondary` passes
    `clientConfig: _getClientConfig()` — version, clientId, appName, appVersion, platform —
    and `NotificationServiceImpl` passes none, so that parameter takes its `const {}`
    default. `AtClientConfig.atClientVersion` therefore reaches the atServer over the verb
    connection only. Whether that is deliberate is unknown: the socket-owning Monitor built
    its own connection, so there was nothing to inherit. Worth settling if the atServer logs
    or branches on client version per connection.
  - **`Monitor` is arguably no longer required.** It is not exported from at_client's barrel,
    has exactly one consumer, and that consumer uses five members — `currentState`,
    `targetState`, `currentStateStream`, `start()`, `stop()`. What is left in it is
    `NotificationServiceImpl`'s own concern, and `Monitor.lastReceipt` is already dead:
    written once, read only by a test, while the public `NotificationService.lastReceipt` is
    served by a second copy. A fold-in would move the watchdog and the retry with it. Not
    started; it is a second structural change and X6 was already large.
  - **`buildRemoteSecondary` is not the only construction site.** `SyncServiceImpl.create`
    builds a `RemoteSecondary` directly rather than through it — functionally equivalent, it
    omits `privateKey` which the constructor recovers from the preference. #2211's own
    description calls `buildRemoteSecondary` "the one place a connection is built", which
    overstates it. Either route sync through it or correct the sentence.
  **Considered and rejected (gkc, 2026-09-06):** a rail asserting
  `AtClientConfig.atClientVersion` matches `pubspec.yaml`. Its dartdoc says the two "must
  always be the same" and nothing enforces it, and the value is sent to the atServer — but
  the bump is a deliberate, infrequent act and the twin stays manual. Do not re-propose
  without new evidence of drift.
  ⚠️ **That evidence arrived the next day.** On `gkc-pq-d1-spike`, commit `cf58ca023` moved
  `at_client`'s `pubspec.yaml` to 3.15.0-rc1 and left `AtClientConfig.atClientVersion` at
  `'3.14.1'`; the drift stood undetected until a cold read on 2026-09-07, and every client
  built from that branch meanwhile told the atServer it was 3.14.1. Fixed on the spike at
  `ea7a33fdf`. One instance is not a rate, and the rejection above may still be right — but
  the "do not re-propose" condition is now satisfied, and a re-proposal should be judged on
  its merits rather than turned away at the door.
  ⚠️ **Merge-back note for the spike:** three sites now read `preference.signingAlgoType`
  directly (`sync_service_impl.dart`, `notification_service_impl.dart`, `remote_secondary.dart`)
  where the spike calls `signingAlgoOf(atClient)`. They must go back to `signingAlgoOf` when PQ
  algorithm resolution lands, or a per-enrollment ML-DSA enrollment signs with the preference's
  algorithm instead of its own.
  ⚠️ **This row previously said "at_cli_commons needed no change".** A later commit on the same
  branch changed it, and its floors were not re-derived afterwards — which is how two of the
  five defects arrived.

**Sequencing.** Each X item lands as its own PR on **trunk** and is merged back into
`gkc-pq-d1-spike` before the next starts, so the drift never accumulates into one large
reconciliation. The one reconciliation worth writing down rather than discovering at
merge time is X4's: `create()` differs between trunk and the spike in three hunks — the
`(atSign, enrollmentId)` cache key (`_resolveCacheKey`), the two `refuse*` guards before `start()`, and
filing under the identity `_init` settled. Keep the key and the filing; **delete
`refuseChangedStoragePath`**, which a bundle holding its own claim makes redundant; keep
`refuseChangedRolloutAxes`. `stop()` is identical on both branches, and
`_stopBackgroundProcesses()` differs only by the spike's `_pqBootstrap?.stop()`. That diff was
measured 2026-09-05 against trunk `ba281fda3`, before X2 and X3 landed; the X4 row's
measurement is against `d13516d95`, after them.

⚠️ **The merge-back rule was not followed for X4, X5 or X6, and the accumulation it exists to
prevent has happened.** X3's merge-back is real — `51bdb6230`, on the spike — but nothing
carried X4, X5 or X6 across, and all three have now merged to trunk. Measured 2026-09-07 with
`git grep -c -F <symbol> <ref> -- 'packages/' 'tests/'`, against a positive control of
`AtClientStorage` at 122 on trunk and 59 on the spike (X2/X3, which did cross):

| Symbol | trunk | `gkc-pq-d1-spike` | Arrived with |
|-------------------------|-------|-------------------|--------------|
| `closedByClient`        | 39    | 0                 | X6           |
| `isolateStorage`        | 24    | 0                 | X5           |
| `AT_FUNCTIONAL_STORAGE` | 2     | 0                 | X5           |
| `monitorSilenceTimeout` | 8     | 0                 | X6           |

Measure the gap by **content, not ancestry** — a squash merge (#2210) leaves no ancestor and
no matching patch-id, so `git cherry` and `git merge-base --is-ancestor` both report work
missing that is present.

✅ **The merge-back was done 2026-09-07**, 43 conflicted files and 127 hunks, and all seven
packages analyze clean afterwards. `refuseChangedStoragePath` was deleted as ruled — the
definition, three call sites and its five covering tests. What that ruling gives up, which was
not written down when it was made: the per-location storage guard subsumes the guard's
*opening* case, but two of the three call sites — `create`'s cache hit and `setPreferences` —
never open anything, so a preference naming a different location is now dropped quietly there.
`create`'s dartdoc says so. Nothing published carried the guard: at_client's last released
version is 3.14.0.

⚠️ **The `signingAlgoOf` note names three files and one of them is wrong.**
`sync_service_impl.dart` and `notification_service_impl.dart` did need it restored.
`remote_secondary.dart` did not: `RemoteSecondary` holds no `AtClient` to pass, and it already
threads the resolution through its own `signingAlgoType` constructor parameter into
`_signingAlgoType`, which is what `_installAuthenticator` reads. Trunk's copy read
`_preference.signingAlgoType` there; keeping the spike's file was the whole fix.

⚠️ **One key-shape defect, met THREE times, and no instance had a compiler behind it.** The
instance map is keyed `(atSign, enrollmentId)` on this branch and by the bare atSign on trunk,
and every lookup written against the old shape still compiles and still returns a value — the
wrong one, or none.

1. **`AtClientImpl.holdsLiveClient`** (trunk, the guard the client factory uses to refuse an
   atSign already live) did `containsKey(fixAtSign(atSign))`, missing every *enrolled* client
   and reporting an atSign free while one was running. Now matches any key for the atSign.
2. **`AtClientImpl.stop()`** unfiled with `atClientInstanceMap.remove(_atSign)` while `create`
   files under `instanceKey(atSign, enrollmentId)` — so a client filed under an enrollment was
   **never unfiled**, and stayed in the map, stopped, for the next caller to be handed and try
   to restart. It now removes **by identity**, which no future key change can break.
3. **Ten test teardowns** did `atClientInstanceMap[atSign]` or `.remove(atSign)`, so an
   enrolled client was never stopped and its storage location stayed claimed for the next test.
   These were most of the 63 unit failures the merge produced.

**When a key gains a component, grep for lookups by the OLD key rather than for the type** —
the type is unchanged, which is exactly why nothing goes red. Prefer identity where the
question is "is this the object I filed", since identity survives the next key change too.

⛔ **The client factory is `buildAtClient(...)`, not a static `AtClient.create`** (gkc, 2026-09-07).
⚠️ **And not `createAtClient` either, which is the name the ruling was taken under.**
`at_onboarding_cli` has exported a top-level `createAtClient` for some time — its own
dartdoc says "this function is exported and apps already call it" — and 1.16.0 is on
pub.dev, so the holder is real and outside this tree. Importing both barrels made the
name ambiguous and eight of at_onboarding_cli's nine test files failed to LOAD, with
`dart analyze` exit 0 on every package: the collision only bites where both are imported,
which is the consuming package's compile.
A static on the interface forces `at_client_spec.dart` to import `at_client_impl.dart`, and
**50 files under `lib/src` import that interface** (49 before the move; `at_client_factory.dart` is the 50th, created BY it — re-derive with `grep -rlE "^\s*(import|export) .*at_client_spec\.dart" packages/at_client/lib/src/ | wc -l`), so the impl — and `enrollment_service_impl`
with it — lands in all 49 import closures. That is the entanglement `import_topology_test.dart`
exists to prevent, and that test is spike-only, which is why X6 shipped the static without
anything going red. Dart cannot put a static outside its class, so the spelling and the
invariant could not both survive; the spelling gave way, at no external cost, because 3.15.0-rc1
is unpublished. The factory now lives in `lib/src/client/at_client_factory.dart`, and moving it
also freed the interface of four impl imports it no longer needs. ⚠️ `js-api.md` still specifies
a JavaScript facade constructed as `AtClient.create(...)`; that is a different language surface
and was deliberately left alone, but the two now differ and the JS design should say why.

⚠️ **Per-enrolment stores exposed that conveyance has no standing subscriber** (found
2026-09-07, while chasing why `nskey_rollout_ladder_live_test` went red under item 3).
An nskey private reaches another enrolment of one atSign by CONVEYANCE, never by a shared
store and never by a shared keyfile — two installs are two devices with two of each. Three
arrival paths exist and the third is missing:

1. **At start** — `collectConveyedKeyMaterial` sweeps waiting envelopes into the keyfile and
   consumes them.
2. **On a read miss** — `privateHalf` fires `_askForMissingPrivate` →
   `requestAndFileNskeyPrivate` → `waitForSecret`, a targeted temporary subscription for one
   secret with a 30s timeout, which files what arrives.
3. **Unsolicited, mid-session — nothing.** `published_nskey_key_ring.dart` says so in its own
   words: "there is no such arrival path mid-session: nothing subscribes to `receivedSecrets`
   to file an nskey private, and `NskeyPrivateFiling.filePending` runs at start."

So **conveyed is not filed**. A proactively conveyed generation sits in the secret store
until the next start, and the first read of anything sealed to it misses once — `privateHalf`
returns null immediately while the ask runs asynchronously — even though the material is
already on the device. `waitForSecret` checks the store first, so the ask then resolves
without a round trip, which is why this has been invisible.

⛔ **Ruled: build a standing subscriber for conveyances** (gkc, 2026-09-07) — nskey privates
and content keys — so an arrival is filed when it lands rather than at the next start.

⚠️ **It is a HANDLER, not a second listener, and the distinction is the whole scope.** There
are two jobs on the one `sweepOnce` path and only one is missing:
- **Answering** another enrollment's request. `_handleRequestPayload` is reachable only from
  `sweepOnce`, so a holder that is not listening never sees a request arriving after its own
  start. This EXISTS — `PqClientBootstrap._startEnvelopeListener` — and its dartdoc records it
  being measured live on 2026-08-17, when "the holder never swept again, and the ask went
  unanswered for the life of the test".
- **Filing an arrival nobody asked for.** Nothing does this. `waitForSecret` files what IT is
  waiting for, and the start sweep files what was already there; an unsolicited conveyance sits
  in the secret store until the next start.
So the subscriber is the missing handler on a listener that already runs, not a new sweep.
⚠️ **One ordering constraint to decide rather than discover**: `collectConveyedKeyMaterial`
CONSUMES and deletes the envelopes it finds at start, and its own dartdoc warns that an app
subscribing afterwards sees no arrival event for anything that was waiting. A standing
subscriber and that start sweep compete for the same envelopes.

⚠️ **That makes THREE states for the ladder test, not two** (gkc asked for two): conveyed
**and filed** reads immediately; conveyed **but not filed** misses once and then resolves from
the store with no round trip; **not conveyed** misses and waits on a holder answering. The
middle state is the one a standing subscriber removes, and it is the one no test covers.

⚠️ **X5's fixture contract is mandatory, and 41 spike files predated it.** `test_utils.dart`
now refuses to hand out storage unless the file called `TestUtils.isolateStorage('<file>')` at
the top of `main()` — a `StateError` naming the fix. Trunk updated its own 20 functional files;
the spike's 41 client-building files were written before the contract existed, so the first
live run after the merge was `+96 -40` with 35 of the 40 failures being that one message. Added
to all 41; `pq_tag_test.dart` is the only file without it, and correctly so — it inspects local
files, talks to no atServer and failed nothing. Each name matches its own file and all 61 are
unique, which is what stops two files sharing a location.

✅ **X4a item 3 is DONE**, in the merge commit `9c84011df`. The item — "rewrite the
multi-enrollment fixtures onto direct `create` with a shared lifecycle-owning test helper" —
was moved off #2208 as spike-side work, and the per-location guard arriving with the merge is
what made it due. What was built differs from the sketch, and the difference is the point:
`FunctionalStorage.forPrincipal(atSign, label)` hands a second LIVE principal its own bundle,
and `enrolAndAuthenticate` DERIVES its own from the device name it already computes, rather
than taking one. One value therefore names both the enrollment and its store, so they cannot
drift; threading a bundle per call site would have meant re-evaluating expressions containing
`uuid.v4()` and silently getting a different label than the enrollment got.
Measured: the functional pack went `+96 -40` → `+195 -6`, principal-collision failures 36 → 1.

⛔ **Succession is not coexistence, and only succession shares a store.** `forPrincipal` is for
two enrollments that are live at once. A retrofit is a succession — the atServer caps the old
enrollment and the new one inherits its data — so it keeps `forAtSign`'s bundle and hands the
store over instead. Both halves are now expressible; before this only one was.

⚠️ **What the store split EXPOSED is worth more than what it fixed.** Two tests were green only
because two "installs" shared one local keystore: `nskey_rollout_ladder_live_test` never
exercised its seal end to end, and `enrollment_test` read records it had never written. That is
the failure mode the whole X series exists to remove, and only separating the stores could show
it. ⛔ **Ruled: sweep for the same shape anywhere two clients of one atSign exist** (gkc,
2026-09-07) — not confined to the nskey family. 42 files build two or more clients; the
shortlist by cross-reads is `tests/at_end2end_test/test/pq/nskey_multi_enrollment_test.dart`
(2 builds / 11 get-put, and the name is the shape), `at_client_lifecycle_functional_test.dart`,
`pq_posture_grid_test.dart` and the unit `enrollment_service_test.dart`.

✅ **All four live packs have been run against the merge, and everything it broke in them
is fixed** (2026-09-07; the post-merge fix-forward section below holds the detail and the
figures). What the packs still fail is #2797's, on the pre-merge backup as much as here. Still
owed from the merge session: the spike was pushed and run through CI on 2026-09-07, the first time since the merge (what the runs showed, and what was fixed, is in the PQ plan's pointer row for the fix-forward);
and [#2218](https://github.com/atsign-foundation/at_client_sdk/pull/2218) is unreconciled.

**Found 2026-09-05 by the wrap-up's cold read and done the same day:** the X3 merge-back
had been skipped. It landed as `51bdb6230`; `at_sync_queue.dart` kept trunk's `SyncQueueStore`
abstraction and the spike's `HiveInstances.forPath(path)` default together, and the queue's
`storagePath` became optional so trunk's SQLite storage compiles on the spike. Also owed:
references to a `plans/wasm/` directory that does not exist. ⚠️ **Recorded as "nine dangling
links" until 2026-09-07, and both halves of that were wrong** (corrected on the spike
2026-09-06, and this copy had not caught up): it is ten lines, one of which names two files,
and only **two** of the ten are markdown links — in `implementation-plan.md`'s T-series rows.
The other eight are prose references that no link checker sees: `decisions.md` ×3,
`js-api.md` ×5.

### Post-merge fix-forward — the analysis, so none of it is re-derived

✅ **The three defects in `principalChange` are FIXED (2026-09-07)**, each pinned by
`packages/at_client/test/at_client_manager_principal_change_test.dart`, which builds the
default shape — an outgoing client owning a store it built from `hiveStoragePath` — and was
red on every case before the fix, and red again under each of two break-it mutations. All
three were introduced by the merge commit `9c84011df` itself and found by the wrap-up's cold
read the same day; `principalChange` had one caller (`self_retrofit.dart`) and no test. What
each was, and what it is now:

1. `stop()` closed the store the switch was about to carry: `_ownsStorage` was true for a
   client-built store, `_releaseStorage` closed it, and `attach()` refused it as closed — so
   the carry worked only for a BORROWED bundle, and the default path failed. Now
   `AtClientImpl.stopHandingOverStorage()` stops the client and returns its store open
   whatever `closedByClient` says, and `setCurrentAtSign` uses it whenever the caller named no
   bundle or named the one the outgoing client holds; the incoming client closes it. The
   `_ownsStorage` field is gone: the store a client builds for itself is now a
   `closedByClient: true` bundle, so which client closes a store is the bundle's say in every
   case — the completion of X6's ruling.
2. The same-atSign short-circuit ignored the flag: `!principalChange` is now among its
   conditions, so a principal change always takes the switch.
3. `selfRetrofit`'s dartdoc recommended a dedicated `AtClientManager(atSign)` "to keep the
   legacy client live alongside"; a fresh manager has no client to hand over, so that shape
   built a second store at the location the legacy client held and was refused. It now says
   what a dedicated manager does — carries nothing, so the retrofitted client needs a
   `storage` of its own.

⚠️ **Two loose ends from the merge session, recorded 2026-09-07 so they are not lost:**
- **[#2218](https://github.com/atsign-foundation/at_client_sdk/pull/2218) is OPEN on trunk**
  and unmerged — `docs(wasm): record X6's merge, and the merge-back it leaves owed`, branch
  `gkc-x6-merge-followup` in the `-x6` worktree, 50 checks green when raised. It corrects
  trunk's copy of this plan; **this branch's copy has moved much further since**, so the two
  will need reconciling rather than one overwriting the other.
- ⚠️ **The merge landed as ONE commit, not the "merge then follow-ups on top" that was asked
  for** (gkc, 2026-09-07). It could not be split: a `packages/`-only merge commit would have
  recorded trunk as merged while carrying the SPIKE's `tests/` — 73 files, including a
  `test_utils.dart` with no `isolateStorage` — i.e. a merge commit not containing the merge.
  And `at_client_impl.dart` and `at_client_manager.dart` each carry the conflict resolution
  AND the later fixes on adjacent lines. So `9c84011df` contains the merge, six production
  fixes, X4a item 3 and the fixture reconciliation together; the message names the layers
  since git cannot.



Everything below was measured on 2026-09-07 against merge commit `9c84011df`. Re-run the
commands rather than quoting the numbers; the METHOD is the part worth keeping.

**Classify failures by pairing each `[E]` with ITS OWN file.** Counting messages globally and
files globally and lining them up is wrong and was wrong twice here — it attributed a
connection error in `self_enrollment_retrofit_live_test` to a storage cause. Walk the log,
and for each `[E]` line take the file from that line and the message from the next non-stack
line beneath it.

**Read a run's log only after it is closed.** `wc -c` on a file a background job is still
appending to measures nothing; two reports of round 7 were built from a half-written log and
both were wrong in the direction of looking like progress. Check for the runner's own summary
line before believing any figure, and translate `\r` before grepping — the expanded reporter
uses carriage returns, so line-based greps under-count files.

**The pack's log grew ~10x at round 8 and that is not a fault.** Two effects: distinct records
synced 229 → 1381, because far more tests now reach the point of writing anything (151 → 195
passing); and pulls-per-record 19 → 26.5, because per-principal stores mean each client syncs
its own. Wall clock 3:13 → 5:11.

**The six functional failures at `9c84011df`, re-measured 2026-09-07 by pairing each `[E]`
with its own file** — which corrected this section's own count: it said two in
`enrollment_test`, and there was one there and one in `nskey_rollout_ladder_live_test`.
- **1, `enrollment_test`** ("atclient get when enrollment request has only read access") —
  ✅ fixed. The enrolled client's `AtChops` had its self-encryption key line commented out,
  which the shared store used to mask; and it read records the owner's client had written
  local-first and never synced. Its chops carry the key now, the owner writes remote-first,
  and the enrolled client reads them from the atServer.
- **1, `nskey_rollout_ladder_live_test`** (state 2's precondition: the holder never
  answered) — ✅ fixed, and the open question below is closed: **the holder's answer store
  was never primed.** The file builds `NskeySeeding` by hand with neither a sharing instance
  nor a filing, so the mint-time `_convey` — which is what puts a minted private into the
  minter's secret store — returned before doing anything, and a holder with no candidate
  answers every request with nothing and logs nothing. The test now primes the store the
  way the bootstrap does at every start, `hydrateStoreFromFiling`, and does so just before
  the conveyance states rather than at the mint, because an answered ask FILES the private
  and the rollout-1 install asks twice before then (at its own start, and while adding to
  the generation). Verified from the log: the request, the answer envelope addressed to the
  requester carrying the request id, and "Filed the nskey private … that a holder conveyed
  on request", 350ms apart.
- **1, `pq_advance_ladder_test`** (a principal collision between two enrollment-scoped
  clients) — ✅ fixed. `clientAt` built every rung on a fresh `AtClientManager(atSign)`
  against `storageForPrincipal(atSign, enrollmentId)`, so rung 0's client still held the
  store when rung 1 asked for it. Every rung is a restart of the one install: the ladder now
  walks the enrolment's own manager and its one bundle (the one `enrolAndAuthenticate` built
  under the device name), the switch stopping the previous rung's client before the next
  attaches — which is also what made the manual cache evict unnecessary.
- **3, `self_enrollment_retrofit_live_test`** — ⛔ **NOT THE MERGE'S**, attributed by the
  two-arm differential this section asked for: the same three cases fail with the same three
  messages ("connection went away" on the legacy session's next verb after the successor's
  first authentication, then `AT0027 … is revoked` twice) on the pre-merge backup and on the
  merged spike, run alone with one invocation against one `at_virtual_env:local` — whose
  binary carries `predecessorSettledAt` and no `apkamSelfEnrollmentGraceHours`. They are
  at_server #2797's immediate revocation of a retrofit predecessor, and belong to the PQ
  table's P1 row "at_server now revokes a non-root retrofit predecessor at the successor's
  first authentication", which already named this file. ✅ **Adapted the same day, at gkc's
  ask:** the full-retrofit arm reads the published key and verifies the key package over the
  legacy connection BEFORE the successor authenticates — the act that revokes it — and the
  switch and rerun arms get their own legacy keyfiles, the rerun submitting twice inside one
  arm and never authenticating its successor. The keyfile's flat id still names the
  predecessor, and that stays right: a cold start resolves the typed material and
  authenticates as the successor. **The functional pack is +201.**

**The other three packs, run 2026-09-07 once the functional pack was green** — every arm on
the same `at_virtual_env:local`, the pre-merge backup run with the same invocation as the
differential:

| Pack                         | At the merge | Pre-merge backup | Now      |
| ---------------------------- | ------------ | ---------------- | -------- |
| e2e, PQ set (10 files)       | +10 -11      | +19 -2           | +19 -2   |
| e2e, non-PQ set (11 files)   | +50 -1       | not run          | +51      |
| onboarding-CLI (6 files)     | +15 -4       | +20 -1           | +20 -1   |

What the merge had broken in them, and the fix for each:
- **Storage collisions** — e2e `nskey_multi_enrollment`, `retrofit_e2e` B1.1 and B1.2,
  `retrofit_retirement`; CLI `pq_native_enroll` and `enrollment_cli_commands`. X4's
  per-location guard refuses a second bundle at a location a live client holds. In the e2e
  pack a second enrollment or a dedicated-manager retrofit was built at the owner's location
  (they used to share it silently); each now gets a `forCoLocatedClient` location named by its
  device. In the CLI pack `evictCachedAtClients()` dropped clients from the cache without
  stopping them, so their claims outlived them; it stops them first now.
- **Stale client references** — e2e `nskey_cross_atsign` ×3, `era_default_read`, and
  `nskey_notify` downstream of it; CLI `enrollment_test` ×2. Before the merge `stop()` left a
  stopped client in the instance cache, so the next `setCurrentAtSign` for that atSign handed
  it back and re-wired its services: a resurrection the tests leaned on across singleton
  switches. `stop()` now unfiles by identity, so a stale reference stays dead. The two e2e
  files run one manager per atSign, both live, and switch nothing; `switchToAtSign` rebuilds
  with the nskey keyfile as well as the credentials (a rebuilt client without it filed nothing
  it minted, and every later client of the atSign adopted a generation it could not open —
  which is what silenced `nskey_notify`); and `AtOnboardingServiceImpl` adopts the client the
  manager built when the one it held has been stopped, leaving an injected client alone.
- **The signing-root client had no storage** — the CLI's PQ-native onboard built it through
  `fromAuthSession` with no bundle, and X6 had moved the service's default off
  `hiveStoragePath`. It is built with the service's storage now.
- **`enrollment_teardown_test` was on no list** — the e2e non-PQ set's one failure was the
  suite manifest naming it; a unit test of the teardown's root check, now allowlisted.

What remained in the three packs was #2797's, and failed on the pre-merge backup too:
`retrofit_cap_value_e2e_test` read a stamp the new server no longer writes,
`retrofit_retirement_e2e_test` expected the cap's exception and got `AT0027 … revoked`, and
the CLI's `at_activate list` after a retrofit-at-start re-authenticated as the revoked legacy
id. ✅ **Adapted 2026-09-07 at gkc's ask** — the catalogue's B1.1, B2.1 and B2.2 now state
the revocation (`docs/projects/pq/acceptance.md`), `retrofit_settlement_e2e_test` (the cap
test renamed) proves it, and the CLI test's enrolment helper authenticates at the legacy
posture so the shipped command, not the test process, performs the retrofit it measures.
⚠️ What that last one exposed is a product question for gkc: `AtAuthImpl.authenticate`
with no enrollment named uses the keyfile's flat id (UC-G1.1 c2, deliberately), which on a
retrofitted keyfile is the superseded predecessor — usable for a month under the old cap,
refused `AT0027` at once under #2797.

**Where the conveyance investigation got to**, so it is not walked again:
- An nskey private reaches another enrollment by CONVEYANCE only. Two installs are two devices
  with two keyfiles and (now) two stores.
- `PublishedNskeyKeyRing.privateHalf` searches memory (`_ownPrivates`) → the filed keyfile copy
  (`NskeyPrivateFiling.read`, which reads `keysIo`, NOT the store) → then fires
  `_askForMissingPrivate` FIRE-AND-FORGET and returns null. The first read after a convey
  therefore always misses.
- The conveyance record lookup DOES fall back to remote (`symmetric_aes_gcm_provider.dart`
  reads `remote: false` then `remote: true`). ⚠️ A `(remote: false)` warning in a log is the
  first of two attempts and is benign; only a `(remote: true)` warning means the atServer had
  nothing. Do not conclude "local-only lookup" from the first — that mistake was made here.
- `askOnReadMiss` defaults **true**, and a ring holding a `privateFiling` derives its own ask,
  so the self-heal is wired by default.
- ⛔ **The holder must be LISTENING to answer, and PRIMED.** `_handleRequestPayload` is
  reachable only from `sweepOnce`, so this file starts the envelope listener by hand (it runs
  `legacyPlusPqProviders` and gets no wired startup tail). That alone did not make state 2
  pass, because a listening holder answers from its secret store, and the by-hand seeding
  never filled it — see the ladder entry above. Both halves are needed, and only the second
  fails silently.

**Fixture helpers, so they are not rebuilt:** `FunctionalStorage.forPrincipal(atSign, label)`
and `TestUtils.storageForPrincipal(atSign, label)` for a second live principal;
`forAtSign`/`storageFor` for the atSign's own; `enrolAndAuthenticate` takes the file's
`FunctionalStorage` and derives its own bundle from the device name.

**Traps met, each of which cost a round:** the `keyfiles` map is keyed by the bare device
(`'ladder-new'`), NOT the deviceName (`'ladder-new-$runId'`); `stopListening()` is synchronous
while `startListening()` is not; `dart analyze lib test` must run from the package root, not
from `test/` (exit 64 is a usage error, not a result); and a `git reset` during a merge
DESTROYS `MERGE_HEAD` — recover by writing `git rev-parse origin/trunk > .git/MERGE_HEAD`
before committing, or the merge records only one parent.

**Deferred to the major:** deprecating `AtClientManager`. Its `AtSignChangeListener`
capability exists only because there is a global current atSign, and where that goes is
undecided, and the migration is large:

```bash
grep -rl 'AtClientManager' --include='*.dart' packages tests | wc -l
```

**Also deferred to the major (ruled 2026-09-05):** `NotificationParams.forUpdate` with no
value is an anti-pattern — the peer is told about a record it must then look up, and a
local-first `put` may not have reached the atServer when it does — and should be refused;
refusing is breaking, so it waits for the major. Until then the hazard is documented on
`useRemoteAtServer` in `request_options.dart`.

**Considered and rejected (2026-09-05):** renaming or re-homing `waitUntilCaughtUp`. It
does wait for pending pushes (`pendingPushCount == 0`), the null-as-zero treatment of that
count is sound for at_client's own sync service, and the extension seam is fine as it is.

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
