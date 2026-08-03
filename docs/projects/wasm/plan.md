# WASM-compatible AtClient

Status: planning. Owner: gkc. Written against `trunk` at `33a062a61`,
2026-08-03.

Goal: an `AtClient` that compiles with `dart compile wasm` and runs in a
browser WasmGC embedding.

The work spans two repositories:

- `at_client_sdk` — the client SDK (this repo).
- `at_server` — specifically `packages/at_persistence_secondary_server`, the
  local-storage layer `at_client` depends on. Published as
  `at_persistence_secondary_server` 5.2.0; `at_client` pins `^5.1.0`.

Contents:

1. [Target and constraints](#1-target-and-constraints)
2. [Goals and non-goals](#2-goals-and-non-goals)
3. [What exists to build on](#3-what-exists-to-build-on) — including the
   [validated `package:sqlite3` compile](#36-validated-packagesqlite3-compiles-under-dart2wasm)
4. [Packaging strategy](#4-packaging-strategy)
5. [Storage backend: SQLite vs raw IndexedDB](#5-storage-backend-sqlite-vs-raw-indexeddb)
6. [High-level plan](#6-high-level-plan)
7. [Acceptance tests](#7-acceptance-tests)
8. [Task backlog](#8-task-backlog)
9. [Open questions](#9-open-questions)

---

## 1. Target and constraints

"WASM-compatible" here means **`dart compile wasm` (dart2wasm / WasmGC),
browser embedding** — not WASI. Dart's `dart compile wasm` only targets the
browser's JS embedding; there is no Dart→WASI toolchain, so the browser
sandbox is the spec.

The constraints:

- **No `dart:io`.** The compiler hard-errors if any *reachable* code
  transitively imports it. Conditional imports with stub files are the only
  fix.
- **No `dart:ffi`.** Same hard error.
- **No `dart:html` / `dart:js`.** dart2wasm dropped them; web interop is
  `dart:js_interop` + `package:web`. The usual "web" fallbacks in third-party
  packages (Hive's IndexedDB backend, `cryptography`'s Web Crypto path) are
  written against `dart:html` and are **not** WASM-safe.
- **Isolates** are experimental under dart2wasm and map to web workers — no
  `Isolate.spawn` with closures.

State of the workspace:

| Signal                            | Count    | Where                                                                                                                          |
| --------------------------------- | -------- | ------------------------------------------------------------------------------------------------------------------------------ |
| `dart:io` in client-path packages | 21 files | `at_client` 7, `at_lookup` 6, `at_utils` 3, `at_auth` 3, `at_chops` 1, `at_server_status` 1                                     |
| `dart:io` in excluded packages    | 14 files | `at_onboarding_cli` 12, `at_cli_commons` 2 — CLI only, never in a WASM build graph                                              |
| `dart:ffi`                        | 8 files  | All in `at_chops` — the OpenSSL-backed PQ algorithms, quarantined behind a separate `at_chops_ffi.dart` barrel                  |
| `dart:isolate`                    | 1 file   | `at_client/lib/src/manager/sync_isolate_manager.dart`, deprecated                                                              |
| `dart:html` / `dart:js`           | 0        | There is no existing web support to lean on                                                                                    |
| Conditional imports               | **0**    | `if (dart.library.…)` appears nowhere in the workspace. Every conditional seam this plan calls for is greenfield.               |

---

## 2. Goals and non-goals

### Goals

1. `dart compile wasm` succeeds on a program that constructs an `AtClient`,
   onboards from `.atKeys` material, reads and writes data, and syncs.
2. One set of core packages. `at_client`, `at_lookup`, `at_auth`, `at_utils`
   and `at_chops` stay single-sourced; platform differences live behind
   conditional imports and the injection seams described in
   [section 3](#3-what-exists-to-build-on).
3. No regression on native. Every conditional seam keeps the existing native
   path byte-for-byte, and the native test suites stay green throughout.
4. Storage work advances the native roadmap, not just WASM. The web SQLite
   path is an additional open strategy under the same `SqliteDatabase`, not a
   parallel backend.

### Non-goals

- **WASI.** Out of scope; there is no Dart→WASI toolchain.
- **Flutter web / Flutter WASM.** `at_client_flutter` and the `at_*_flutter`
  UI packages are a separate, unsupported track. This project targets the
  headless `AtClient` in a browser JS embedding.
- **CLI packages.** `at_onboarding_cli` and `at_cli_commons` are excluded from
  the WASM build graph and need no porting.
- **File transfer on web** in the first milestone. See
  [task backlog group D](#d-deferred).
- **Server-side changes.** None are required; see
  [3.4](#34-the-atserver-already-accepts-websocket-connections).

---

## 3. What exists to build on

Two subsystems carry almost all the risk — transport and local storage — and
both are already reachable behind abstractions. The work is "implement one
more backend", not "design a new seam".

### 3.1 The persistence layer is backend-agnostic and has two backends

`at_persistence_secondary_server` 5.2.0 provides:

- **A fully backend-agnostic spec** under `lib/src/spec/` —
  `KeyValueStore<K,V>`, `AtKeyValueStore<K,V,T>`, `AtPersistenceFactory`,
  `AtPersistenceBundle`, `AtPersistenceBackendId`, plus the commit-log,
  access-log and notification-keystore interfaces. No spec changes are needed
  for WASM.
- **Four barrels**, so impls are opt-in rather than transitively reachable:
  `at_persistence_secondary_server.dart` (spec, factory abstractions and
  migration only), `hive.dart`, `sqlite.dart`, `dual.dart`. The main barrel
  names no impl, so importing it does not drag `dart:io` in.
- **Hive-free model classes.** `AtData`, `AtMetaData`, `CommitEntry`,
  `AccessLogEntry` and `AtNotification` are plain classes under `src/spec/`;
  the `@HiveType` annotations and `TypeAdapter`s live in
  `src/impl/hive/adapters/`.
- **A SQLite backend** (`lib/sqlite.dart`): `SqliteAtKeyValueStore`,
  `SqliteAtCommitLog`, `SqliteAtAccessLog`, `SqliteAtNotificationKeystore`,
  `SqliteAtPersistenceFactory`, `SqliteDatabase`, `SqliteSchema`. One
  `atsign.db` per atSign; the per-atSign schema is a documented interchange
  contract. It is the only backend with `supportsSnapshots` and
  `supportsPathQueries` both true, and with real atomic transactions.
- **Migration and comparison tooling** — `PersistenceMigrator` (a
  backend-agnostic Hive↔SQLite copy), `PersistenceSnapshot` (a canonical
  bundle comparator) and `bin/compare_persistence.dart`, backed by a
  conversion-integrity gate in which hive→sqlite→hive→sqlite round-trips
  byte-identically.

**The whole store surface is asynchronous.** `get`, `put`, `create`, `remove`,
`getExpiredKeys`, `deleteExpiredKeys`, `nextExpiresAt`, `peekExpired`,
`getKeys`, `exists`, `getMany`, `removeMany`, `transaction`, `snapshot`,
`stats`, `scanKeys`, `putMeta`, `putAll`, `getMeta`, `restore` and
`nextAvailableAt` all return futures; `getKeys` and `scanKeys` return
`Future<Stream<…>>`. Only `changes` (a `Stream`), `queryByPath` (a `Stream`)
and the `supportsSnapshots` / `supportsPathQueries` booleans are synchronous.
This matters for the backend choice in
[section 5](#5-storage-backend-sqlite-vs-raw-indexeddb): there is no
sync-returning method that a fully-async browser storage API could not
honour.

On the client side, `at_client` is commit-log-free —
`bundle.keyValueStore.commitLog` is null for client bundles, and sync is
tracked by `AtSyncQueue` plus the synced-commit-id watermark.
`local_secondary.dart` imports the main barrel and the spec type, and
`storage_manager.dart` builds its bundle through `AtPersistenceFactory` /
`AtPersistenceBundle`.

**What is missing.** The SQLite backend is native-only:
`src/impl/sqlite/sqlite_database.dart` imports `dart:io`, calls
`DynamicLibrary.open` (to work around Linux shipping `libsqlite3.so` only in
the `-dev` package) and `Directory(dir).createSync`;
`sqlite_at_commit_log.dart` and `sqlite_at_access_log.dart` use `File`.
It also types its handle as `Database` — the `dart:ffi` flavour from
`package:sqlite3/sqlite3.dart` — and the stores import that same entry point.

The dual-platform path is available and has been validated to compile; see
[3.6](#36-validated-packagesqlite3-compiles-under-dart2wasm).

### 3.6 Validated: `package:sqlite3` compiles under dart2wasm

`package:sqlite3`'s web support predates WasmGC, so whether it survives
`dart compile wasm` rather than only `dart2js` was the plan's largest
unvalidated assumption. It was checked directly, on Dart 3.11.3 against
`sqlite3` 2.9.4 (what the package's `^2.4.0` constraint resolves to):

| Probe | Result |
| ----- | ------ |
| Import `package:sqlite3/wasm.dart`, load via `WasmSqlite3.loadFromUrl`, register an `IndexedDbFileSystem` VFS, open a database, `CREATE TABLE` / `INSERT` / `SELECT` | **Compiles.** 187.8 KB `.wasm` |
| Same, but with the handle typed as `CommonDatabase` and `execute` / `prepare` / `select` called through it | **Compiles.** 187.5 KB `.wasm` |
| **Negative control:** import `package:sqlite3/sqlite3.dart` (the FFI entry point) and open an in-memory database | **Fails**, as it must — `Dart library 'dart:ffi' is not available on this platform`, at `sqlite3-2.9.4/lib/src/ffi/api.dart:1`. No output produced. |
| **Baseline:** empty `main` printing a string | 11.6 KB `.wasm` |

The negative control confirms the toolchain does reject the FFI path, so the
positive results are meaningful rather than an artefact of a permissive
compile. The 11.6 KB → 187.8 KB delta confirms the bindings are genuinely
compiled in rather than tree-shaken away.

This also sizes the split in [P3](#p-persistence-at_server--at_persistence_secondary_server).
`package:sqlite3/common.dart` exists precisely for this — it "exports common
interfaces that are implemented by both the `dart:ffi` and the `dart:js` WASM
version of this library" — and the FFI `Database extends CommonDatabase`. So
the conditional split is narrow: retype `SqliteDatabase`'s handle and `raw`
getter to `CommonDatabase`, repoint the stores from
`package:sqlite3/sqlite3.dart` to `package:sqlite3/common.dart`, and put only
the `open` call behind the conditional import. The store bodies do not change.

**What this does not establish:** runtime behaviour. Fetching the
`sqlite3.wasm` blob, the IndexedDB VFS actually persisting, and query
execution in a real browser are all untested — this was a compile check only.
Gates B3 and X2 cover the runtime claim.

Two client-side couplings also stand in the way. `storage_manager.dart`
constructs `HiveAtPersistenceFactory()` as a field and requires
`AtClientPreference.hiveStoragePath`, so the backend is not selectable from
`AtClientPreference`. And `at_client/lib/src/sync/at_sync_queue.dart` imports
`package:hive/hive.dart` directly, opening
`Hive.openBox<String>('syncqueue_<sha256(atSign)>')` against the global Hive
instance in the same directory the keystore uses. `at_client`'s pubspec
carries a direct `hive: ^2.2.3` dependency for it.

### 3.2 Injection seams already in place

- `AtLookupSecureSocketFactory` and `AtLookupSecureSocketListenerFactory` are
  constructor params of `AtLookupImpl`. The leak is their **return type**
  (`SecureSocket`), not their injectability.
- `SecondaryAddressFinder` is an abstract interface, and the
  `rootDomain: 'proxy:<host>'` convention bypasses root lookup entirely —
  two independent ways to avoid the raw TLS socket to `root.atsign.org:64`.
- `probeSocket` is an injectable `Function?` on `AtAuthImpl`; only its
  `SecureSocket.connect` default needs to become conditional.
- `atKeysIo` is injectable on the onboarding request. `AtKeysIo` is a `sealed`
  class with `WrittenAtKeysIo` / `GeneratedAtKeysIo` subtypes, and both
  `FileAtKeysIo` and `InMemoryAtKeysIo` exist — so a web key store is a new
  subtype, not a new abstraction.
- `AtSyncQueue` takes an injected box, so it has a seam to generalise from.

### 3.3 `at_chops` separates its pure-Dart and FFI surfaces

`at_chops` ships two barrels. `at_chops.dart` exports only pure-Dart
algorithms — including `ml_kem_768_pure_dart.dart`,
`ml_dsa_65_pure_dart.dart`, `x_wing_pure_dart.dart` and
`x25519_pure_dart_algo.dart`. `at_chops_ffi.dart`, documented "not web/wasm
compatible", re-exports `at_chops.dart` plus the eight OpenSSL-backed FFI
files. Nothing in any package's `lib/` imports the FFI barrel; only
`at_chops`'s own tests and examples do.

So the FFI island is correctly quarantined. The residual risk is that the
separation is held by convention alone, which is what acceptance gate A4
exists to ratchet. `dart_periphery` — also FFI-based, also used only under
`example/` — sits in `at_chops`'s `dependencies:` and should move to
`dev_dependencies:`.

The sharper crypto risk is the pure-Dart path itself. `cryptography` backs
`x_wing_pure_dart.dart`, `x25519_pure_dart_algo.dart`, `aes_gcm.dart`,
`x25519_key_pair.dart`, `argon2id.dart` and `at_chops_util.dart`;
`pqcrypto` backs `ml_kem_768_pure_dart.dart` and `ml_dsa_65_pure_dart.dart`;
`better_cryptography` backs `aes.dart`, `aes_ctr_factory.dart`,
`ed25519.dart` and `at_chops_util.dart`. These are the algorithms a WASM build
must use, so a WASM-hostile path in any of them is a critical-path failure
rather than a missing fallback. `cryptography` 2.x's browser path in
particular uses Web Crypto via `dart:html`.

`pointycastle`, `crypto`, `crypton`, `encrypt`, `ecdsa` and `elliptic` are
pure Dart and WASM-fine. In `at_client`, `cron` (pure-Dart `Timer`),
`archive`, `http` (fetch on web) and `uuid` are fine as-is. `at_commons`,
`at_contact`, `at_policy`, `base2e15` and `dart_utf7` need no work.

### 3.4 The atServer already accepts WebSocket connections

On `at_server` trunk, `at_secondary_impl.dart` wraps the TLS `ServerSocket` in
a `PseudoServerSocket`, runs an `HttpServer` over it, and upgrades
`GET /ws` via `WebSocketTransformer.upgrade` into
`inboundConnectionManager.createWebSocketConnection(...)`. The WebSocket
connection writes the same `'@'` prompt on accept as the raw socket path.

Consequences for the client:

- The endpoint is `wss://<secondary-host>:<secondary-port>/ws` — the **same
  port** as the Atsign Protocol socket, selected by ALPN (a
  `selectedProtocol` that is neither null nor `atProtocol/1.0` routes to
  HTTP). No new port, no new server deployment.
- The framing is identical, so the existing verb/response parser is reusable
  unchanged. Only the byte transport swaps.
- **No server-side work is required for the transport.** The whole transport
  problem is client-side.

### 3.5 Where `dart:io` currently sits on the client path

| Package            | Files | Detail |
| ------------------ | ----- | ------ |
| `at_client`        | 7     | `client/at_client_spec.dart` (`List<File>` in `uploadFile` / `downloadFile` / `reuploadFiles`), `client/at_client_impl.dart` (`File`, `Directory`, `Platform.pathSeparator`, `deleteSync`), `client/remote_secondary.dart` (`SecureSocketConfig`, `getSocket().add(data)`), `manager/monitor.dart` (`getSocket().listen(...)`, `SocketException`), `service/file_transfer_service.dart`, `service/encryption_service.dart` (`encryptFileInChunks` / `decryptFileInChunks`), `stream/stream_notification_handler.dart` |
| `at_lookup`        | 6     | `connection/at_connection.dart` (the interface leaks `Socket getSocket()`), `connection/base_connection.dart` (`late final Socket _socket`, `socket.destroy()`, `socket.remoteAddress`), `at_lookup_impl.dart`, `monitor_client.dart` (`SecureSocket.connect`), `util/secure_socket_util.dart` (`SecureSocket.connect`, `SecurityContext`, `File` for cert and TLS-keylog paths), `cache/cacheable_secondary_address_finder.dart` (raw TLS socket to `root.atsign.org:64`) |
| `at_utils`         | 3     | `networking/pseudo_server_socket.dart` (`ServerSocket` / `SecureServerSocket`), `config/app_config.dart` (`File`, to read YAML), `logging/handlers.dart` (`FileLoggingHandler` plus `stderr` / `stdout` handlers) |
| `at_auth`          | 3     | `keys/io/file_io.dart` (`File`, `Directory`, `getHomeDirectory()` switching on `Platform.operatingSystem`), `at_auth_impl.dart` (`atKeysIo ??= FileAtKeysIo()` default, `_defaultProbeSocket`'s `SecureSocket.connect`), `registrar/registrar_service.dart` (`HttpClient()`) |
| `at_chops`         | 1     | `algorithm/ffi/openssl_loader.dart`, inside the quarantined FFI island |
| `at_server_status` | 1     | `model/at_status.dart` — the import is **unused**; no `dart:io` type is referenced in the file |

Two of these are reachable purely because of barrel shape:
**`at_utils.dart` exports `networking/pseudo_server_socket.dart` and
`config/app_config.dart`**, so both break a WASM build for every `at_utils`
consumer. `PseudoServerSocket` is not dead code — `at_server` uses it to
ALPN-multiplex HTTP over the Atsign Protocol TLS port — so the fix is a barrel
split, not a deletion.

Separately, `at_client.dart` exports `at_client_spec.dart`, so `dart:io File`
is reachable from the public client surface. As long as `File` appears in a
reachable signature, the whole client fails to compile to WASM.

---

## 4. Packaging strategy

Keep **one set of core packages**; do not fork `at_client`. Use **conditional
imports** (`if (dart.library.io)` / `if (dart.library.js_interop)`) plus the
injection seams in [3.2](#32-injection-seams-already-in-place).

New packages:

| Package         | Status   | Purpose |
| --------------- | -------- | ------- |
| `at_client_web` | new      | Platform glue, playing the role `at_client_flutter` plays for mobile — wires the WebSocket transport, the web storage backend, `WebAtKeysIo`, web connectivity and a console logger. App authors depend on this. |
| `at_transport`  | optional | Transport abstraction plus native and web impls. Can instead live inside `at_lookup`; decide when the abstraction is written. |

Everything else is conditional-import surgery inside existing packages.

Two structural moves recur, and both follow patterns already used in this
codebase: **split a barrel** so a platform-specific surface is opt-in
(`at_persistence_secondary_server`'s four barrels and `at_chops`'s two are the
models), and **make a default conditional** where the abstraction is already
injectable but its default constructor names `dart:io`.

---

## 5. Storage backend: SQLite vs raw IndexedDB

Two ways to give the browser a local store behind the keystore spec: compile
SQLite to WASM, or implement the spec directly against IndexedDB object
stores.

Because the store surface is fully asynchronous
([3.1](#31-the-persistence-layer-is-backend-agnostic-and-has-two-backends)),
**both are implementable.** There is no sync-returning method to force an
in-memory key-index cache or a cross-package caller migration. The choice is
therefore about fidelity, reuse and payload size rather than feasibility.

### 5.1 What each backend can honour

| Spec member | SQLite-wasm | IndexedDB |
| ----------- | ----------- | --------- |
| `get` / `put` / `create` / `remove` | Yes | Yes — object-store ops. |
| `getMany` / `removeMany` | Yes | Yes — loop inside one IDB transaction. |
| `exists` | Yes | Yes — `count()` on the key. |
| `getExpiredKeys` / `deleteExpiredKeys` / `nextExpiresAt` / `peekExpired` | Yes — indexed on `expiry` | Needs an **index on the expiry timestamp**; otherwise full scan. |
| `getKeys(regex:)` | Yes | Cursor walk plus a Dart regex. Regex has no IDB equivalent. |
| `scanKeys(KeyPattern)` | Yes — indexed on the structured columns | Cursor walk. The structured filters map to IDB indexes only if `sharedBy` / `sharedWith` / `namespace` / `idPrefix` are stored as separate indexed fields; otherwise full scan plus in-memory filter. |
| `changes` stream | Yes | Yes — app-level broadcast controller. |
| `transaction` | Yes — true atomic transactions | IDB has real transactions, but they **auto-close on the first `await` of non-IDB work**. The spec's buffer-mutations-then-apply `KeyStoreTxn` model fits (buffer in Dart, flush in one IDB txn), but nested awaits inside `body` are a footgun. |
| `supportsSnapshots` / `snapshot` | `true` | `false` — IndexedDB has no snapshot isolation. |
| `supportsPathQueries` / `queryByPath` | `true` — a real indexed query | `false` unless composite indexes are hand-built. |
| `stats` | Yes | Cursor count / `count()`. |

### 5.2 The case for SQLite

- **The backend already exists.** `SqliteAtKeyValueStore` and its siblings are
  written, published, and covered by a conversion-integrity gate. The web work
  is a conditional-import open path plus gating three `File` uses — materially
  less than a from-scratch backend.
- **Fidelity.** SQLite is the only backend that honours the full spec.
  IndexedDB permanently returns `false` for snapshots and path queries.
- **Shared native payoff.** Every fix to the SQLite store benefits the native
  and server backends. A raw IndexedDB backend is WASM-only effort.
- **One schema.** The per-atSign `atsign.db` schema is a documented
  interchange contract, and `PersistenceMigrator` / `PersistenceSnapshot`
  already compare two backends for one atSign. A browser database that is
  byte-comparable with a desktop one is worth having.

The case for IndexedDB is **payload size only.** `sqlite3.wasm` is a ~1 MB+
blob shipped to the browser on top of the compiled Dart.

> **Recommendation: SQLite-wasm is the WASM storage backend.** Hold raw
> IndexedDB in reserve purely as a payload-size mitigation. Because the async
> spec surface makes it a straightforward backend implementation rather than a
> cross-package migration, that decision can be revisited late, on a measured
> payload number, rather than committed to up front.

### 5.3 VFS choice

`package:sqlite3/wasm.dart` offers two persistence strategies, and the choice
sets `at_client_web`'s execution model:

- **`IndexedDbFileSystem`** — works on the main thread, loads the database on
  open, flushes asynchronously. Simpler; no worker.
- **OPFS** — true synchronous access, requires a dedicated web worker.

Deferred to a measurement; see [open questions](#9-open-questions).

---

## 6. High-level plan

Five phases. Phases 1–3 are largely independent and can proceed in parallel;
phase 4 is the integration point that produces the first successful build.

**Phase 1 — Persistence (web SQLite).** In `at_server`'s
`at_persistence_secondary_server`: retype the handle to `CommonDatabase` and
split `SqliteDatabase`'s `open` behind a conditional import, so the native
path keeps `dart:ffi` + `dart:io` and a new web path opens via
`sqlite3/wasm.dart` and a VFS. The compile feasibility of that web path is
[already validated](#36-validated-packagesqlite3-compiles-under-dart2wasm).
Gate the `File` uses in
`sqlite_at_commit_log.dart` and `sqlite_at_access_log.dart` — both are on the
log stores, which client bundles do not instantiate, so gating rather than
porting is sufficient for the client. Extend `SqlitePersistenceConfig` with
the web open parameters (database name, VFS choice).

**Phase 2 — Transport.** In `at_lookup` (or a new `at_transport`): define an
`AtTransport` abstraction with no `dart:io` in its surface; implement
`transport_io.dart` (wrapping `SecureSocket`) and `transport_web.dart`
(wrapping `WebSocket` from `package:web`); select by conditional barrel.
Remove `Socket getSocket()` from `AtConnection` — a **breaking change for
`implements` users**, so audit downstream first (`at_client`'s
`remote_secondary.dart` and `monitor.dart` both call it). Change the
`AtLookupSecureSocketFactory` return type from `SecureSocket` to the transport
interface. Point the web impl at `wss://<host>:<port>/ws`.

**Phase 3 — `dart:io` sweep.** Conditional imports and barrel splits across
`at_utils`, `at_auth`, `at_client` (excluding file transfer) and
`at_server_status`; delete `sync_isolate_manager.dart`; verify the `at_chops`
pure-Dart dependencies actually compile under dart2wasm; swap connectivity off
`internet_connection_checker`; factor `dart:io File` out of the reachable
`AtClient` surface.

**Phase 4 — `at_client_web` and first build.** New glue package; make the
persistence backend selectable from `AtClientPreference`; give `AtSyncQueue`
a backend-neutral store. Target: first successful `dart compile wasm`, then
first live browser session against a real atServer.

**Phase 5 — Deferred.** File-transfer web implementation, browser onboarding
and key-import UX, Argon2id performance.

---

## 7. Acceptance tests

Each gate is a command with a checkable outcome. Gates A1–A4 are the ratchet:
once green, they run on every subsequent commit.

### A. Compile gates

| ID | Gate | Definition of done |
| -- | ---- | ------------------ |
| A1 | **Reachability probe.** A minimal program that imports `package:at_client/at_client.dart` and constructs nothing else compiles under `dart compile wasm`. | Exit 0, no `dart:io` / `dart:ffi` reachability error. This is the earliest signal and should go green before any behaviour work. |
| A2 | **Full-surface compile.** A program that builds an `AtClient` via `AtClientManager`, onboards from in-memory `.atKeys` material, and calls `put` / `get` / `delete` / `getKeys` compiles under `dart compile wasm`. | Exit 0. |
| A3 | **Native non-regression.** `dart analyze --fatal-warnings` and the full `dart test --concurrency=1` suite stay green in every package touched by a conditional seam, at every commit boundary. | Zero new failures. Refactors touching connection or storage lifecycle additionally require the functional suite — see X1. |
| A4 | **Seam enforcement.** An automated check asserts that no file reachable from `package:at_client/at_client.dart`, `package:at_lookup/at_lookup.dart`, `package:at_utils/at_utils.dart`, `package:at_auth/at_auth.dart` or `package:at_chops/at_chops.dart` transitively imports `dart:io`, `dart:ffi`, `dart:html`, `dart:js` or `dart:isolate` other than through a `dart.library` conditional. | Check runs in CI and fails the build on violation. Without this, A1 and A2 silently rot the first time someone adds an import. |

### B. Browser runtime gates

| ID | Gate | Definition of done |
| -- | ---- | ------------------ |
| B1 | **Transport handshake.** A browser page loads the WASM module, opens `wss://<host>:<port>/ws` against a virtualenv atServer, and receives the `'@'` prompt. | Prompt observed; `from` / `pkam` complete. |
| B2 | **Authenticated round trip.** The same page performs `update` then `lookup` for a self key and reads back the value it wrote. | Value matches. |
| B3 | **Storage persistence across reload.** Write a key, reload the page, read it back from local storage without touching the network (`remoteLocalPref` unset). | Value survives the reload. |
| B4 | **Sync.** A key written by a native client for the same atSign appears in the browser client's local storage via the normal sync path, and vice versa. | Both directions observed. Exercises `AtSyncQueue` on its backend-neutral store. |
| B5 | **Cross-atSign encrypted share.** Browser client shares a key with a second atSign; a native client for that atSign decrypts it. | Plaintext matches. Confirms the pure-Dart crypto path is correct, not merely compiling. |
| B6 | **Onboarding from pasted `.atKeys`.** `.atKeys` content pasted into the page decrypts (Argon2id in pure Dart) and yields a working `AtClient`. | Session authenticates. Record the wall-clock decryption time — it is the phase-5 UX input. |

### X. Cross-tier gates

| ID | Gate | Definition of done |
| -- | ---- | ------------------ |
| X1 | **Functional and e2e suites.** `tests/at_functional_test` and `tests/at_end2end_test` `runLocal.sh` both green after the transport and storage changes, with `docker compose down` before each run. | Both green. The `AtConnection` change is a wire-path change; unit-green is not done. |
| X2 | **Persistence conversion integrity.** The hive→sqlite→hive round-trip gate stays green, and `bin/compare_persistence.dart` reports identical for a native-SQLite vs web-SQLite database written from the same workload. | Exit 0 from both. Proves the web open path produces the same on-disk schema, not merely a working one. |
| X3 | **Payload budget.** Measure and record the shipped byte total: compiled `.wasm` + `sqlite3.wasm` + JS glue, gzipped and Brotli. | A recorded number. This is the input to the SQLite-vs-IndexedDB decision in [section 5](#5-storage-backend-sqlite-vs-raw-indexeddb) — record it before deciding, not after. |

---

## 8. Task backlog

Grouped by phase. Ordering within a group is roughly dependency order.

### P. Persistence (`at_server` / `at_persistence_secondary_server`)

- **P1** — ~~Verify `package:sqlite3`'s web entry point compiles under
  dart2wasm.~~ **Done.** It does, with a passing negative control; see
  [3.6](#36-validated-packagesqlite3-compiles-under-dart2wasm).
- **P2** — Decide the VFS (`IndexedDbFileSystem` vs OPFS) on a measurement,
  and record the decision. Blocks P3's web path and sets `at_client_web`'s
  execution model.
- **P3** — Split `src/impl/sqlite/sqlite_database.dart` behind a conditional
  import. Native path keeps `dart:io`, `DynamicLibrary.open` (the Linux
  `libsqlite3.so.0` soname workaround) and `Directory().createSync`. Web path
  opens via `package:sqlite3/wasm.dart` with a VFS and `package:web`.
  Prerequisite, and the bulk of the work: retype `SqliteDatabase`'s `_db`
  field and `raw` getter from `Database` to `CommonDatabase`, and repoint the
  four stores from `package:sqlite3/sqlite3.dart` to
  `package:sqlite3/common.dart`. Only the `open` call itself needs the
  conditional; the store bodies are unchanged.
- **P4** — Gate the `File` uses in `sqlite_at_commit_log.dart` (line ~185) and
  `sqlite_at_access_log.dart` (line ~104). Both are on log stores that client
  bundles do not instantiate; confirm that and gate rather than port.
- **P5** — Extend `SqlitePersistenceConfig` with web open parameters
  (database name, VFS choice) alongside the native `storagePath`.
- **P6** — Add a `SqlitePersistenceConfig.clientDefaults(...)` equivalent for
  the commit-log-free client bundle shape, mirroring
  `HivePersistenceConfig.clientDefaults`.

### T. Transport (`at_lookup`)

- **T1** — Define `AtTransport`: `Stream<List<int>>` inbound, a sink,
  `connect()` / `close()`, metadata. No `dart:io` in its surface.
- **T2** — Audit every `implements AtConnection` and `getSocket()` caller
  before changing the interface — `at_client`'s `remote_secondary.dart` and
  `manager/monitor.dart` at minimum, plus any external implementor.
  **Breaking change**; enumerate the blast radius first.
- **T3** — Remove `Socket getSocket()` from
  `src/connection/at_connection.dart`; replace with a transport handle.
- **T4** — Follow through in `src/connection/base_connection.dart`
  (`late final Socket _socket`, `socket.destroy()`, `socket.remoteAddress`),
  `outbound_connection.dart`, `outbound_connection_impl.dart`.
- **T5** — `transport_io.dart` wrapping `SecureSocket`; move
  `src/util/secure_socket_util.dart` (`SecureSocket.connect`,
  `SecurityContext`, `File` for cert and TLS-keylog paths) behind it as
  native-only.
- **T6** — `transport_web.dart` wrapping `WebSocket` from `package:web`,
  targeting `wss://<host>:<port>/ws`. Framing is unchanged, so the existing
  response parser is reused as-is.
- **T7** — Conditional barrel selecting by `dart.library.io` /
  `dart.library.js_interop`.
- **T8** — `src/at_lookup_impl.dart`: change `AtLookupSecureSocketFactory` and
  `AtLookupSecureSocketListenerFactory` return types from `SecureSocket` to
  the transport interface. The factories are already injectable; the return
  type is the leak.
- **T9** — `src/monitor_client.dart`: `SecureSocket.connect` for the monitor
  stream follows the transport change.
- **T10** — Root lookup. `src/cache/cacheable_secondary_address_finder.dart`
  opens a raw TLS socket to `root.atsign.org:64`. Ship a web
  `SecondaryAddressFinder` using one of the two existing escape hatches (the
  abstract interface, or the `proxy:` convention); a WebSocket- or
  HTTPS-reachable directory endpoint is the longer-term answer.
- **T11** — Decide whether `AtTransport` and its impls live in `at_lookup` or
  a new `at_transport` package. Defer until T1 is written.

### I. `dart:io` sweep

- **I1** — `at_utils`: split the barrel. `at_utils.dart` exports
  `src/networking/pseudo_server_socket.dart` (`ServerSocket` /
  `SecureServerSocket`) and `src/config/app_config.dart` (`File`), making both
  reachable from every consumer. `PseudoServerSocket` is used by `at_server`
  for ALPN multiplexing, so split it into a server-side barrel; do not delete.
- **I2** — `at_utils`: `src/logging/handlers.dart`. `FileLoggingHandler` plus
  `stderr` / `stdout` handlers. The **default** handler must become web-safe
  (`print` / console); file and stderr handlers stay behind the conditional
  import.
- **I3** — `at_utils`: make `app_config.dart` conditional, or inject config.
- **I4** — `at_auth`: make `src/keys/io/file_io.dart` native-only behind a
  conditional import.
- **I5** — `at_auth`: add `WebAtKeysIo` as a `WrittenAtKeysIo` subtype.
  `InMemoryAtKeysIo` already exists, so this may reduce to a thin persistence
  wrapper over IndexedDB or wrapped WebCrypto rather than a new decode path.
- **I6** — `at_auth`: `src/at_auth_impl.dart` line ~227,
  `atOnboardingRequest.atKeysIo ??= FileAtKeysIo()` — make the default
  platform-conditional, or the web build pulls in `dart:io` regardless of
  what the caller injects.
- **I7** — `at_auth`: `_defaultProbeSocket` uses `SecureSocket.connect`
  (line ~396). `probeSocket` is already an injectable `Function?`, so only the
  default needs to become conditional.
- **I8** — `at_auth`: `src/registrar/registrar_service.dart` uses
  `HttpClient()` from `dart:io`. Swap to `package:http`, which works on WASM
  via fetch.
- **I9** — `at_client`: delete `src/manager/sync_isolate_manager.dart`. It is
  `@Deprecated`, used only by the deprecated `SyncManager`, and is the only
  `dart:isolate` file. The live sync path does not use it.
- **I10** — `at_client`: replace `internet_connection_checker` (raw-socket
  host probes) in `src/listener/connectivity_listener.dart` and
  `src/client/remote_secondary.dart`. Prefer an injectable connectivity
  interface over swapping to `internet_connection_checker_plus`; the browser
  impl then uses `navigator.onLine` plus fetch probes. Drop the dependency
  from `pubspec.yaml`.
- **I11** — `at_client`: `src/client/remote_secondary.dart` —
  `SecureSocketConfig` plumbing and `getSocket().add(data)` follow T3.
- **I12** — `at_client`: `src/manager/monitor.dart` — `getSocket().listen(...)`
  and `SocketException` follow T3.
- **I13** — `at_server_status`: delete the unused `dart:io` import from
  `src/model/at_status.dart`. One line.
- **I14** — File transfer: factor it out of the reachable core surface.
  `src/client/at_client_spec.dart` names `List<File>` in `uploadFile`,
  `downloadFile` and `reuploadFiles`, and `at_client.dart` exports the spec —
  so as long as `File` appears in a reachable signature the whole client fails
  to compile. Either change the API to take `(bytes, name)` or a stream
  abstraction, or move file transfer into a separate optional
  `AtFileTransfer` component (native-only for now). Pulls
  `src/client/at_client_impl.dart` (`File`, `Directory`,
  `Platform.pathSeparator`, `deleteSync`),
  `src/service/file_transfer_service.dart`,
  `src/service/encryption_service.dart`
  (`encryptFileInChunks` / `decryptFileInChunks`) and
  `src/stream/stream_notification_handler.dart` with it.

### C. Crypto (`at_chops`)

- **C1** — Confirm **`cryptography`** resolves to a **pure-Dart**
  implementation under dart2wasm. Its 2.x browser path uses Web Crypto via
  `dart:html`, which dart2wasm does not have. Critical path: it backs
  `encryption/x_wing_pure_dart.dart`, `encryption/x25519_pure_dart_algo.dart`,
  `encryption/aes_gcm.dart`, `key/impl/x25519_key_pair.dart`,
  `hashing/argon2id.dart` and `util/at_chops_util.dart`. Pin, configure, or
  replace.
- **C2** — Confirm **`pqcrypto: ^0.3.0`** compiles under dart2wasm. Also
  critical path: it backs `encryption/ml_kem_768_pure_dart.dart` and
  `signing/ml_dsa_65_pure_dart.dart`, the algorithms a WASM build uses in
  place of the FFI ones. Note `ml_kem_768_pure_dart.dart` reaches into
  `package:pqcrypto/src/…` for `KyberLevel` — a private-path import that could
  break on any upstream release.
- **C3** — Confirm **`better_cryptography`** (used by
  `util/at_chops_util.dart`, `encryption/aes.dart`,
  `encryption/aes_ctr_factory.dart`, `signing/ed25519.dart`) compiles under
  dart2wasm. It is a fork of `cryptography` with unknown WASM status.
- **C4** — No structural work on the FFI split: the `at_chops.dart` /
  `at_chops_ffi.dart` barrels are already the right shape. Confirm no `lib/`
  code in any package imports the FFI barrel, and let gate A4 hold it.
  Revisit only if the FFI path ever needs to become a runtime default, at
  which point the split has to become a `dart.library`-conditional seam
  rather than two barrels.
- **C5** — Move `dart_periphery` from `dependencies:` to `dev_dependencies:`.
  It is FFI-based and used **only under `example/`**; it is tree-shaken from a
  real build but should not sit in the dependency graph.
- **C6** — Measure Argon2id in pure Dart on WASM. It will be noticeably slow;
  the number is the phase-5 UX input for `.atKeys` passphrase decryption
  (gate B6).

### G. Glue and wiring

- **G1** — Make the persistence backend selectable from `AtClientPreference`.
  `src/manager/storage_manager.dart` hardcodes `HiveAtPersistenceFactory()`
  and requires `hiveStoragePath`. Introduce a backend choice
  (`AtPersistenceBackendId` already has `hive` and `sqlite`) and an opaque
  storage location that means a path on native and a database name on web.
- **G2** — Give `AtSyncQueue` a backend-neutral store.
  `src/sync/at_sync_queue.dart` opens `Hive.openBox<String>` directly against
  the global Hive instance. Add a small spec interface with Hive and SQLite
  impls, matching how the keystore is factored. It already has an injected-box
  test seam to build on.
- **G3** — Drop the direct `hive: ^2.2.3` dependency from `at_client`'s
  pubspec once G1 and G2 land.
- **G4** — New `at_client_web` package: WebSocket transport wiring, web
  storage backend, `WebAtKeysIo`, web connectivity, console logger.
- **G5** — Browser test harness for gates B1–B6: a page that loads the module
  and drives a virtualenv atServer.
- **G6** — Wire gate A4 (seam enforcement) into CI.

### D. Deferred

- **D1** — File-transfer web implementation via `package:web` File/Blob.
- **D2** — Browser onboarding and key-import UX. The `.atKeys` *file* does not
  exist in a browser; the flow needs paste, upload or QR feeding bytes into
  the existing decode path.
- **D3** — Argon2id performance work, driven by C6's measurement.
- **D4** — Raw IndexedDB backend, only if gate X3's payload measurement rules
  `sqlite3.wasm` out.

---

## 9. Open questions

1. ~~**Does `package:sqlite3`'s web entry point compile under dart2wasm?**~~
   **Answered: yes**, on Dart 3.11.3 against `sqlite3` 2.9.4, with a negative
   control that fails as expected. See
   [3.6](#36-validated-packagesqlite3-compiles-under-dart2wasm). Runtime
   behaviour in a browser remains unproven and is covered by gates B3 and X2.
2. **Which VFS?** `IndexedDbFileSystem` (main thread, async flush) or OPFS
   (true sync, needs a web worker). Sets `at_client_web`'s execution model.
   Task P2.
3. **What is the acceptable WASM payload budget?** Compiled `.wasm` +
   `sqlite3.wasm` + JS glue. Informs the SQLite-vs-IndexedDB fallback in
   [section 5](#5-storage-backend-sqlite-vs-raw-indexeddb). Gate X3.
4. **Do `at_chops`'s crypto dependencies compile under dart2wasm?**
   `cryptography`, `pqcrypto` and `better_cryptography`. The first two are the
   sharper question: both underpin the pure-Dart PQ algorithms a WASM build
   must use, so a WASM-hostile path there is a critical-path failure, not a
   missing fallback. Tasks C1, C2 and C3.
5. **Directory lookup from a browser.** `root.atsign.org:64` is a raw TLS
   socket. The `proxy:` convention and the injectable
   `SecondaryAddressFinder` unblock development, but a production browser
   client needs a WebSocket- or HTTPS-reachable directory endpoint. Whose
   work is that, and does it belong in this project? Task T10.
6. **Does `package:hive` compile to WASM as a dead stub?** Hive 2.x's internal
   conditional imports *should* resolve to the no-op `stub` backend under
   dart2wasm (both `dart.library.html` and `dart.library.io` are false). It
   gates whether G3 is required or merely tidy. Needs a compile test.
7. **How far does `AtConnection`'s breaking change reach outside this repo?**
   T2 covers the in-repo callers; external `implements` users are unknown.
