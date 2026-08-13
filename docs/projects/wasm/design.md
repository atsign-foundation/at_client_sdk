# design.md — Capability seams, by subsystem

**Status:** working design doc. Lives in `docs/projects/wasm/`.
**Purpose:** the per-capability design — for each platform capability the core
currently reaches for directly, the current call sites (`file:line`), the interface
that replaces them, and who implements it on each platform.
**Lane:** this doc owns *how it is built and where the code lives*. For the thesis see
[`roadmap.md`](roadmap.md); for sequencing see
[`implementation-plan.md`](implementation-plan.md); for the gates see
[`acceptance.md`](acceptance.md); for the rulings see [`decisions.md`](decisions.md);
for the non-Dart consumer story see [`js-api.md`](js-api.md).
**Verified against:** `trunk` at `20f7f4da5`, 2026-08-13.

## Table of contents

- [0. What already exists to build on](#0-what-already-exists-to-build-on)
- [1. The `_io` barrel pattern](#1-the-_io-barrel-pattern)
- [2. Capability inventory](#2-capability-inventory)
  - [2.1 Transport](#21-transport)
  - [2.2 Storage bootstrap](#22-storage-bootstrap)
  - [2.3 The sync queue](#23-the-sync-queue)
  - [2.4 Key material — the exemplar](#24-key-material--the-exemplar)
  - [2.5 HTTP](#25-http)
  - [2.6 Connectivity](#26-connectivity)
  - [2.7 Logging](#27-logging)
  - [2.8 Filesystem and file transfer](#28-filesystem-and-file-transfer)
  - [2.9 Process and environment](#29-process-and-environment)
  - [2.10 Crypto](#210-crypto)
  - [2.11 Explicitly out of scope — clock, timers, random](#211-explicitly-out-of-scope--clock-timers-random)
- [3. Dead-end seams — the cheapest first move](#3-dead-end-seams--the-cheapest-first-move)
- [4. `AtClientPreference` is a bag of strings, not a bag of capabilities](#4-atclientpreference-is-a-bag-of-strings-not-a-bag-of-capabilities)
- [5. Storage backend — SQLite-wasm vs raw IndexedDB](#5-storage-backend--sqlite-wasm-vs-raw-indexeddb)

---

## 0. What already exists to build on

Three pieces of prior work carry most of the risk, and all three are already in good
shape. None of this is new design.

### 0.1 The atServer already accepts WebSocket connections

On `at_server` trunk, `at_secondary_impl.dart` wraps the TLS `ServerSocket` in a
`PseudoServerSocket`, runs an `HttpServer` over it, and upgrades `GET /ws` via
`WebSocketTransformer.upgrade` into
`inboundConnectionManager.createWebSocketConnection(...)`. The WebSocket path writes
the same `'@'` prompt on accept as the raw socket path.

- Endpoint: `wss://<secondary-host>:<secondary-port>/ws` — the **same port** as the
  Atsign Protocol socket, selected by ALPN. No new port, no new deployment.
- Framing is identical, so the existing verb/response parser is reused unchanged. Only
  the byte transport swaps.
- **No server-side work is required.** The transport problem is entirely client-side.

### 0.2 The persistence layer is backend-agnostic, with two backends

`at_persistence_secondary_server` 5.2.x provides a fully backend-agnostic spec
(`KeyValueStore<K,V>`, `AtKeyValueStore<K,V,T>`, `AtPersistenceFactory`,
`AtPersistenceBundle`, `AtPersistenceBackendId`), four opt-in barrels (main / `hive` /
`sqlite` / `dual`), Hive-free model classes, a complete SQLite backend, and
migration/comparison tooling with a byte-identical round-trip gate.

**The whole store surface is asynchronous** — `get`, `put`, `create`, `remove`,
`getExpiredKeys`, `getKeys`, `scanKeys`, `transaction`, `snapshot`, `stats` and the
rest all return futures. Only `changes`, `queryByPath` and the two `supports*` booleans
are synchronous. No spec change is needed for a browser backend, and no caller
migration is forced by one.

On the client side `at_client` is commit-log-free: `bundle.keyValueStore.commitLog` is
null for client bundles, and sync is tracked by `AtSyncQueue` plus the synced-commit-id
watermark.

**Validated 2026-08-03:** `package:sqlite3`'s web entry point compiles under dart2wasm
(Dart 3.11.3, `sqlite3` 2.9.4) — `WasmSqlite3.loadFromUrl` + `IndexedDbFileSystem` VFS
+ `CREATE TABLE`/`INSERT`/`SELECT`, 187.8 KB module, against an 11.6 KB empty-`main`
baseline. The negative control (the `dart:ffi` entry point) failed as required. The
conditional surface is narrow: retype `SqliteDatabase`'s handle and `raw` getter from
`Database` to `CommonDatabase`, repoint the stores at `package:sqlite3/common.dart`,
and only the `open` call differs. Store bodies do not change.

This is a **compile** result. Runtime behaviour in a browser remains unproven, and is
covered by [`acceptance.md`](acceptance.md) T3.1 and X1.

### 0.3 at_chops separates its pure-Dart and FFI surfaces

`at_chops.dart` exports only pure-Dart algorithms, including the PQ ones
(`ml_kem_768_pure_dart.dart`, `ml_dsa_65_pure_dart.dart`, `x_wing_pure_dart.dart`,
`x25519_pure_dart_algo.dart`). `at_chops_ffi.dart`, documented "not web/wasm
compatible", re-exports it plus the eight OpenSSL-backed FFI files. **No package's
`lib/` imports the FFI barrel** — only at_chops's own tests and examples.

The island is correctly quarantined; it is held by convention, which is what T0
converts into enforcement. This is the one area where T1 (`dart compile wasm`) has
real value, since `dart:ffi` *is* hard-rejected.

---

## 1. The `_io` barrel pattern

Every capability below follows the same three-part shape.

**In the neutral package**, the interface and nothing else:

```dart
// package:at_lookup/at_lookup.dart  — no dart:io anywhere in this graph
abstract interface class AtTransport {
  Future<void> connect();
  Stream<List<int>> get inbound;
  void write(List<int> bytes);
  Future<void> close();
}
```

**In the same package, a second barrel** carrying the native implementation:

```dart
// package:at_lookup/at_lookup_io.dart
export 'at_lookup.dart';
export 'src/io/secure_socket_transport.dart';  // the only file naming dart:io
```

**In the platform package**, the web implementation:

```dart
// package:at_client_web/at_client_web.dart
class WebSocketTransport implements AtTransport {
  // ...
}
```

Three rules make this work, and they are rulings rather than style —
[`decisions.md`](decisions.md) D-1, D-2, D-5:

1. **No `if (dart.library.*)` in a neutral package.** The core must not know platforms
   differ.
2. **No default that names an implementation.** `x ??= NativeThing()` re-imports the
   native graph regardless of what the caller injects, and is the single most common
   way a barrel split silently fails. Require injection instead.
3. **No throwing stub.** If a platform lacks a capability, the type is not constructible
   there. `throw UnsupportedError` in a fallback is a defect, not a port.

Rule 2 is why this is a breaking-change program. There is no additive way to remove a
default.

---

## 2. Capability inventory

### 2.1 Transport

**The largest item.** Everything that reaches an atServer terminates in one function.

| Site                                                                        | What it does                                                                                                                                                                                                       |
| --------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `at_lookup/lib/src/util/secure_socket_util.dart:12,23,25,29,35,43,49,54,55` | `SecurityContext.defaultContext`, cert `File`, `setTrustedCertificates`, `SecureSocket.connect` ×2, `setOption(tcpNoDelay)` ×2, TLS-keylog `File` + append-write. **Every connection in every package ends here.** |
| `at_lookup/lib/src/monitor_client.dart:63`                                  | `SecureSocket.connect(host, int.parse(port))` — raw, bypasses even `SecureSocketUtil`.                                                                                                                             |
| `at_client/lib/src/stream/stream_notification_handler.dart:27`              | `SecureSocket.connect(host, port)` — raw.                                                                                                                                                                          |
| `at_client/lib/src/manager/monitor.dart:539`                                | `SecureSocketUtil.createSecureSocket(...)` inside the default `MonitorOutboundConnectionFactory`.                                                                                                                  |
| `at_lookup/lib/src/cache/cacheable_secondary_address_finder.dart:209,222`   | raw TLS socket to `root.atsign.org:64` for directory lookup.                                                                                                                                                       |
| `at_auth/lib/src/at_auth_impl.dart:396`                                     | `_defaultProbeSocket` → `SecureSocket.connect`. **Owned by the PQ program's S-5**, not here.                                                                                                                       |

**The ABI leak** is the interface, not the implementation:

- `at_lookup/lib/src/connection/at_connection.dart:10` — `Socket getSocket();`
- `at_lookup/lib/src/connection/base_connection.dart:10,14,50` — `late final Socket
  _socket`, `BaseConnection(Socket? socket)`, `socket.destroy()`,
  `socket.remoteAddress`
- `at_lookup/lib/src/at_lookup_impl.dart:740,749,756` — the three factory classes
  return and accept `SecureSocket`

**Design.** Define `AtTransport` with no `dart:io` in its surface: an inbound
`Stream<List<int>>`, a sink, `connect()`/`close()`, and connection metadata. Remove
`Socket getSocket()` from `AtConnection` and replace it with a transport handle. Retype
`AtLookupSecureSocketFactory`, `AtLookupSecureSocketListenerFactory` and
`AtLookupOutboundConnectionFactory` onto it — they are *already injectable*, so the
return type is the entire blocker.

**Implementers.** `at_lookup_io.dart` wraps `SecureSocket` and absorbs
`secure_socket_util.dart` whole (certs and TLS keylog are native-only concerns).
`at_client_web` wraps `WebSocket` from `package:web`, targeting
`wss://<host>:<port>/ws`. Framing is unchanged, so the response parser is reused as-is.

**Breaking-change blast radius.** `Socket getSocket()` is on a public interface;
external `implements AtConnection` users are unknown. In-repo callers are
`at_client/lib/src/client/remote_secondary.dart` and
`at_client/lib/src/manager/monitor.dart`. Enumerate before changing.

**Directory lookup.** `root.atsign.org:64` is a raw TLS socket with no browser
equivalent. Two escape hatches already exist — `SecondaryAddressFinder` is an abstract
interface, and the `rootDomain: 'proxy:<host>'` convention bypasses root lookup
entirely. Either unblocks development; a production browser client needs a WebSocket-
or HTTPS-reachable directory endpoint, which is an open question in
[`decisions.md`](decisions.md).

### 2.2 Storage bootstrap

The keystore *is* injectable. Its bootstrap is not.

```dart
// at_client/lib/src/manager/storage_manager.dart:16
final HiveAtPersistenceFactory _factory = HiveAtPersistenceFactory();
```

`final`, no constructor parameter, `package:at_persistence_secondary_server/hive.dart`
imported directly. `_initStorage` then requires `preferences!.hiveStoragePath` and
throws `'Please set local storage path'` when it is null. The chain runs
`AtClientImpl._init()` (`at_client_impl.dart:392-399`) → `StorageManager.init(...)` →
`HiveAtPersistenceFactory().initialize(...)` → `Hive.init(storagePath)` +
`Directory(storagePath)` inside `at_persistence_secondary_server`.

`StorageManager.init(String currentAtSign, List<int>? keyStoreSecret)` accepts
`keyStoreSecret` and never uses it — worth removing while in the area.

**The existing escape hatch:** `AtClientImpl.create(..., localSecondaryKeyStore:)`.
When non-null, `StorageManager` is skipped entirely and `LocalSecondary` takes the
injected store. Good, but it means a web caller must construct the whole store itself
rather than choosing a backend.

**Design.** Make the factory selectable from `AtClientPreference` —
`AtPersistenceBackendId` already carries `hive` and `sqlite`. Replace `hiveStoragePath`
with an opaque storage location that means a filesystem path on native and a database
name on web (§4). Add a `SqlitePersistenceConfig.clientDefaults(...)` mirroring
`HivePersistenceConfig.clientDefaults` for the commit-log-free client bundle shape.

### 2.3 The sync queue

**The canonical runtime landmine, and the one to lead with when explaining this
project.**

```text
// at_client/lib/src/sync/at_sync_queue.dart:121
_box = await Hive.openBox<String>(boxNameForAtSign(_atSign));
```

Opened lazily from `LocalSecondary._ensureSyncQueueOpen()`
(`local_secondary.dart:110-134`), against the **global Hive singleton**, assuming
someone already called `Hive.init`. `local_secondary.dart:118-121` documents that
ordering dependency in a comment — it is an implicit global contract, not an enforced
one.

Consequences: it fires on the first `put` or `syncQueueSize`, not at construction; it
compiles everywhere; and injecting a keystore to bypass `StorageManager` makes it throw
rather than fixing it. `at_client`'s pubspec carries a direct `hive: ^2.2.3` dependency
solely for this file.

**Design.** A small spec interface with Hive and SQLite implementations, matching how
the keystore is factored. A test seam already exists — `open({Box<String>? injectedBox})`
at `at_sync_queue.dart:116`, documented as a test seam at `:85-89` — but it is not
reachable from `AtClientImpl.create`, so plumbing it is a cheap intermediate step (§3).
Drop the direct `hive` dependency once this and §2.2 land.

### 2.4 Key material — the exemplar

**Already correct. Cite it; do not redesign it.**

`at_auth/lib/src/keys/io/at_keys_io.dart:15` — `sealed class AtKeysIo`, with
`WrittenAtKeysIo` (`:24`) and `GeneratedAtKeysIo` (`:57`). Three implementations exist
across three platforms:

| Impl               | Home                                                          | Platform                                      |
| ------------------ | ------------------------------------------------------------- | --------------------------------------------- |
| `FileAtKeysIo`     | `at_auth/lib/src/keys/io/file_io.dart`                        | native (moves to `at_auth_io.dart` under S-5) |
| `InMemoryAtKeysIo` | `at_auth/lib/src/keys/io/memory_io.dart`                      | any                                           |
| `KeychainAtKeysIo` | `at_client_flutter/lib/src/keychain/keychain_io_impl.dart:10` | Flutter                                       |

Injected through `AtClientImpl.create(atKeysIo:)` (`at_client_impl.dart:311,386`) and
`AtClientManager` (`:81`). This is a neutral interface, multiple real implementations,
one supplied by a platform package — exactly the shape every other capability here
should reach.

Its one flaw is the shape rule 2 warns about: `at_auth_impl.dart:227` still does
`atOnboardingRequest.atKeysIo ??= FileAtKeysIo()`, which pulls `dart:io` into the graph
no matter what the caller injects. **The PQ program's S-5 removes it.**

`at_client_web` adds a web `WrittenAtKeysIo` subtype. Because `InMemoryAtKeysIo`
already handles the decode path, this should reduce to a thin persistence wrapper over
IndexedDB or WebCrypto-wrapped storage — a new subtype, not a new abstraction.

### 2.5 HTTP

| Site                                                               | State                                                                                                                                                                 |
| ------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `at_auth/lib/src/registrar/registrar_service.dart:34`              | `IOClient(HttpClient())` — but `http.Client? httpClient` is an injectable constructor param at `:26`. Only the default is native. **S-5 moves it to `package:http`.** |
| `at_client/lib/src/service/file_transfer_service.dart:14,31,40,50` | Top-level `http.post` / `http.StreamedRequest` / `http.get`. **No injection at all.**                                                                                 |

`package:http` works under WASM via `fetch`, so the fix is an injected `http.Client`
rather than a new abstraction. File transfer is deferred (§2.8), but the client
injection is worth doing regardless — it is also the only way to test that service.

### 2.6 Connectivity

`internet_connection_checker` performs raw-socket host probes and is imported directly
by `at_client/lib/src/client/remote_secondary.dart:14` and
`at_client/lib/src/listener/connectivity_listener.dart:3`. The reachability calls are
`remote_secondary.dart:188` (`InternetAddress.lookup`) and `:192`
(`InternetConnectionChecker().isHostReachable`), both inside the deprecated
`isAvailable()`; `connectivity_listener.dart:44-50` uses
`InternetConnectionChecker.createInstance(...)`, and that whole class is already
`@Deprecated` while still being exported from `at_client.dart:11`.

**Design.** An injectable connectivity interface, not a swap to
`internet_connection_checker_plus`. The web implementation is `navigator.onLine` plus
fetch probes; the native one keeps today's behaviour. Drop the dependency. Given both
call sites are already deprecated, deleting rather than porting is worth evaluating
first.

### 2.7 Logging

The interface is right; its packaging is not.

- `at_utils/lib/src/logging/handlers.dart:9-12` — `LoggingHandler { void call(LogRecord) }`,
  with four implementations.
- `at_utils/lib/src/logging/handlers.dart:1` — `import 'dart:io';` **in the same file**,
  so importing the logger at all drags `dart:io` in. `FileLoggingHandler` (`:34-48`),
  `StdErrLoggingHandler` (`:53-59`) and `CLILoggingHandler` (`:71-97`) are the users.
- `at_utils/lib/src/logging/atsignlogger.dart:14-22` — a mutable process-global static
  `defaultLoggingHandler`, defaulting to `ConsoleLoggingHandler` → `print`.

`print` works under WASM, so this is not a crash — it is a graph problem plus a global.
Split the file: `ConsoleLoggingHandler` stays in the neutral barrel, the three native
handlers move to `at_utils_io.dart`.

**Also in `at_utils`:** `at_utils.dart:4-5` unconditionally exports
`src/networking/pseudo_server_socket.dart` (`ServerSocket`, `SecureServerSocket`) and
`src/config/app_config.dart` (`File`, reading YAML). Both break every consumer of the
package. `PseudoServerSocket` is **not** dead code — `at_server` uses it for ALPN
multiplexing — so this is a barrel split, not a deletion.

### 2.8 Filesystem and file transfer

**The ABI-level leak that blocks everything else.**
`at_client/lib/src/client/at_client_spec.dart:653-679` names `dart:io File` in the
public interface — `uploadFile(List<File>, ...)`,
`downloadFile(...) → Future<List<File>>`, `reuploadFiles(List<File>, ...)`,
`shareFiles(...)` — and `at_client.dart:4` exports the spec. While `File` appears in a
reachable signature, no amount of internal work makes the client neutral.

The implementation trail behind it: `at_client_impl.dart:1214,1389-1394,1456-1482`
(`File`, `Directory().create()`, `.copy()`, `.listSync`, `deleteSync(recursive:)`);
`encryption_service.dart:310,313,323,342,350` (`encryptFileInChunks` /
`decryptFileInChunks`); `file_transfer_service.dart:58,62`;
`stream_notification_handler.dart:29,51,57`.

**Design — two options, decide at execution.** Either change the API to take
`(bytes, name)` or a stream abstraction, or move file transfer into a separate optional
`AtFileTransfer` component that is native-only for now. The second is smaller and
matches the deferral in [`roadmap.md`](roadmap.md) §4; the first is the better API. The
choice is recorded as an open question in [`decisions.md`](decisions.md).

### 2.9 Process and environment

`Platform.pathSeparator` at `at_client_impl.dart:1363,1390,1394,1469-1476`,
`encryption_service.dart:310,314,343`, `stream_notification_handler.dart:30,58`,
`file_transfer_service.dart:62`; `Platform.operatingSystem` and
`Platform.environment['HOME'/'USERPROFILE']` at `at_auth/lib/src/keys/io/file_io.dart:162-174`.

Every one of these sits inside a filesystem operation. They leave with §2.8 and with
S-5 respectively — there is no separate "process" seam to design.

`at_client/lib/src/manager/sync_isolate_manager.dart` is the only `dart:isolate` file
in any `lib/`. It is `@Deprecated("Only used by deprecated SyncManager")`, carries
`// coverage:ignore-file`, and has **zero** references anywhere in `packages/` outside
itself. Delete it. (Note that T1 would never flag it — `dart:isolate` compiles under
dart2wasm, [`acceptance.md`](acceptance.md) §1.1.)

### 2.10 Crypto

No structural work: the `at_chops.dart` / `at_chops_ffi.dart` barrels are already the
right shape (§0.3), and T0 holds them.

The real risk is the **pure-Dart path itself**, because a WASM build has no fallback —
these are the algorithms it must use:

| Package               | Backs                                                                                                                                |
| --------------------- | ------------------------------------------------------------------------------------------------------------------------------------ |
| `cryptography`        | `x_wing_pure_dart.dart`, `x25519_pure_dart_algo.dart`, `aes_gcm.dart`, `x25519_key_pair.dart`, `argon2id.dart`, `at_chops_util.dart` |
| `pqcrypto`            | `ml_kem_768_pure_dart.dart`, `ml_dsa_65_pure_dart.dart`                                                                              |
| `better_cryptography` | `aes.dart`, `aes_ctr_factory.dart`, `ed25519.dart`, `at_chops_util.dart`                                                             |

`cryptography` 2.x's browser path uses Web Crypto via `dart:html`. `pqcrypto` is
additionally fragile: `ml_kem_768_pure_dart.dart` reaches into
`package:pqcrypto/src/…` for `KyberLevel`, a private-path import that can break on any
upstream release. `better_cryptography` is a `cryptography` fork with unknown web status.

**The compile target changes what this question even asks.** Under dart2wasm,
`dart:html` is rejected, so `cryptography` *must* fall back to pure Dart — and pure-Dart
Argon2id is the reason `.atKeys` decryption was expected to be slow enough to need
deferred UX work ([`acceptance.md`](acceptance.md) T4.6). Under **dart2js**, which
[`decisions.md`](decisions.md) D-7 selects, `dart:html` compiles — so the Web Crypto path
is reachable and may activate automatically.

So C1 is no longer "will it compile?" but:

1. Which implementation does `cryptography` select under dart2js?
2. If it is Web Crypto, how much faster are Argon2id and AES?
3. Does that remove the deferred Argon2id work outright?

**Measure before assuming either way** — and note that a dependency silently relying on
the deprecated `dart:html` is a risk to track, not a licence for our own code to use it
(T0.1 keeps it on the forbidden list for package-owned sources).

All three packages are verifiable **by execution** rather than by compile — the at_chops
suite runs under [`acceptance.md`](acceptance.md) T2.3. That is a strictly better answer
than the predecessor doc's compile check, and it closes the same questions.

`pointycastle`, `crypto`, `crypton`, `encrypt`, `ecdsa` and `elliptic` are pure Dart
and fine. `dart_periphery` sits in at_chops's `dependencies:` despite being FFI-based
and used only under `example/` — move it to `dev_dependencies:`.

### 2.11 Explicitly out of scope — clock, timers, random

There is no `Clock` seam anywhere, and `DateTime.now()` / `Timer` / `Future.delayed` /
`Uuid().v4()` appear throughout sync, monitor, the address-finder cache and the secret-
sharing code.

**All of it is portable under WASM.** Injecting these would improve testability
materially — the SDK is hard to test deterministically today — but it is **not a port
requirement**, and folding it in would enlarge every diff in this project for a benefit
that belongs to a different one. Recorded here so it is visibly a decision rather than
an oversight.

---

## 3. Dead-end seams — the cheapest first move

Four injection points already exist and are simply never passed through. Plumbing them
changes no interface, breaks nothing, and shrinks every later diff.

| Seam                                                                                                      | Defined at                                                                            | Never passed by                                                                                                                      |
| --------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------ |
| `AtLookupSecureSocketFactory`, `AtLookupSecureSocketListenerFactory`, `AtLookupOutboundConnectionFactory` | `at_lookup/lib/src/at_lookup_impl.dart:740,749,756`, constructor params at `:108-131` | `RemoteSecondary` — `at_client/lib/src/client/remote_secondary.dart:44-56` builds `AtLookupImpl` without any of them                 |
| `MonitorOutboundConnectionFactory`                                                                        | `at_client/lib/src/manager/monitor.dart:531`, constructor param at `:93`              | `NotificationServiceImpl._` — `notification_service_impl.dart:76-84`; `create` exposes only `monitor:` and `secondaryAddressFinder:` |
| `AtSyncQueue.open({injectedBox})`                                                                         | `at_client/lib/src/sync/at_sync_queue.dart:116`                                       | Not reachable from `AtClientImpl.create`                                                                                             |
| `http.Client`                                                                                             | `at_auth/lib/src/registrar/registrar_service.dart:26`                                 | Plumbed — listed for completeness; the default is the only native part                                                               |

The second `RemoteSecondary` construction at `at_client_impl.dart:1225` (the
stream/file-transfer path) is not injectable at all and needs the same treatment.

**The catch:** these factories are typed in terms of `dart:io SecureSocket`/`Socket`,
so plumbing them does not by itself enable a web implementation. It is preparation —
it puts the wiring in place so that §2.1's retype is a type change rather than a type
change *plus* a plumbing change.

---

## 4. `AtClientPreference` is a bag of strings, not a bag of capabilities

`at_client/lib/src/preference/at_client_preference.dart` has **no `dart:io` import**.
It carries platform-specific configuration as `String?`:

| Field             | Line | Reaches                                             |
| ----------------- | ---- | --------------------------------------------------- |
| `hiveStoragePath` | 10   | `Hive.init`                                         |
| `commitLogPath`   | 13   | vestigial — client bundles are commit-log-free      |
| `downloadPath`    | 66   | file transfer                                       |
| `tlsKeysSavePath` | 112  | `File(...).writeAsStringSync` in `SecureSocketUtil` |
| `pathToCerts`     | 115  | `SecurityContext.setTrustedCertificates`            |
| `decryptPackets`  | 109  | gates the TLS keylog write                          |
| `keyStoreSecret`  | 37   | passed to `StorageManager.init` and ignored         |

**This is the mechanism by which native-only configuration compiles on web and fails at
runtime.** A path is a string everywhere; it only stops meaning anything when something
tries to open it. The type system never objects.

**Design.** `AtClientPreference` should carry *capabilities* alongside its tuning
knobs, and the filesystem paths should become an opaque storage location whose
interpretation belongs to the backend — a directory on native, a database name on web.

Two precedents in the same class and its neighbour show the shape:

- `at_client_preference.dart:158` — `CryptoConfig crypto`, a configured provider seam
  resolved at runtime by `CryptoRuntime`.
- `at_client_manager.dart:265` — `AtServiceFactory`, the existing service-level DI hook,
  with `DefaultAtServiceFactory` at `:291` and a real override already shipping in both
  CLI packages (`ServiceFactoryWithNoOpSyncService`).

Whether platform capabilities hang off `AtClientPreference` or off `AtServiceFactory` is
an open question in [`decisions.md`](decisions.md). `AtServiceFactory` is the closer
analogue; `AtClientPreference` is what callers already touch.

---

## 5. Storage backend — SQLite-wasm vs raw IndexedDB

Because the store surface is fully asynchronous (§0.2), **both are implementable**.
There is no sync-returning method that would force an in-memory key index or a
cross-package caller migration. The choice is about fidelity, reuse and payload size,
not feasibility.

| Spec member                                                              | SQLite-wasm                             | IndexedDB                                                                                                                                                                 |
| ------------------------------------------------------------------------ | --------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `get` / `put` / `create` / `remove`                                      | Yes                                     | Yes — object-store ops                                                                                                                                                    |
| `getMany` / `removeMany`                                                 | Yes                                     | Yes — loop inside one IDB transaction                                                                                                                                     |
| `exists`                                                                 | Yes                                     | Yes — `count()` on the key                                                                                                                                                |
| `getExpiredKeys` / `deleteExpiredKeys` / `nextExpiresAt` / `peekExpired` | Yes — indexed on `expiry`               | Needs an index on the expiry timestamp, else full scan                                                                                                                    |
| `getKeys(regex:)`                                                        | Yes                                     | Cursor walk plus a Dart regex — no IDB equivalent                                                                                                                         |
| `scanKeys(KeyPattern)`                                                   | Yes — indexed on the structured columns | Cursor walk; maps to indexes only if `sharedBy`/`sharedWith`/`namespace`/`idPrefix` are stored as separate indexed fields                                                 |
| `changes` stream                                                         | Yes                                     | Yes — app-level broadcast controller                                                                                                                                      |
| `transaction`                                                            | Yes — true atomic transactions          | Real, but IDB transactions **auto-close on the first `await` of non-IDB work**. The buffer-then-apply `KeyStoreTxn` model fits; nested awaits inside `body` are a footgun |
| `supportsSnapshots` / `snapshot`                                         | `true`                                  | `false` — no snapshot isolation                                                                                                                                           |
| `supportsPathQueries` / `queryByPath`                                    | `true`                                  | `false` unless composite indexes are hand-built                                                                                                                           |
| `stats`                                                                  | Yes                                     | Cursor count / `count()`                                                                                                                                                  |

**Ruling: SQLite-wasm is the WASM storage backend.** The backend already exists, is
published, and is covered by a conversion-integrity gate; it is the only backend that
honours the full spec; every fix benefits native and server too; and one schema means a
browser database is byte-comparable with a desktop one.

The case for IndexedDB is **payload size only** — `sqlite3.wasm` is a ~1 MB+ blob on
top of the compiled Dart. Hold it in reserve as a payload mitigation. Because the async
spec surface makes it a straightforward backend implementation rather than a migration,
that decision can be revisited late, on the measured number from
[`acceptance.md`](acceptance.md) X2, rather than committed to up front.

**VFS choice** — `IndexedDbFileSystem` (main thread, loads on open, flushes
asynchronously; no worker) vs **OPFS** (true synchronous access, requires a dedicated
web worker). This sets `at_client_web`'s execution model and is deferred to a
measurement; open question in [`decisions.md`](decisions.md).
