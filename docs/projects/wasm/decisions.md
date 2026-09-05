# decisions.md — Rulings, measured findings & open questions

**Status:** decision record (binding).
**Scope:** the rulings D-1..D-9 that govern the implementation-neutral `AtClient`
work, the measurements that drove them, the superseded positions from the predecessor
`plan.md`, the open questions, and a dated log.
**Lane:** this doc owns *why*, not *how* or *when*. Mechanics live in
[`design.md`](design.md); sequencing in [`implementation-plan.md`](implementation-plan.md);
gates in [`acceptance.md`](acceptance.md); the thesis in [`roadmap.md`](roadmap.md); the
non-Dart consumer story in [`js-api.md`](js-api.md).

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

**Amended 2026-08-27 — one shipped exception, and the reason it is not a precedent.**
`at_auth` 4.0.0-rc1 ([#2179](https://github.com/atsign-foundation/at_client_sdk/pull/2179))
ships `lib/src/auth/probe_default.dart`, a conditional export selecting the reachability
probe: `probe_default_web.dart`, or `probe_default_io.dart` under `dart.library.io`.

It stands, because the premise of this ruling does not hold for it. D-1 rejects
conditionals on the grounds that the non-native branch is a stub. Here **both branches are
real implementations, and the choice is not substitutable**: an atServer answers an HTTP
GET only when the TLS handshake negotiates `http/1.1` over ALPN, which a browser does as a
matter of course and `package:http`'s VM client does not — the same GET on the VM lands on
the atServer's line protocol and comes back `@error:AT0003`. A TLS handshake is what is
available under `dart:io`, and it is sufficient there. Injection is still offered:
a caller wanting the other probe, or any other, sets `probeSocket`.

What this costs. The ban specified as [`acceptance.md`](acceptance.md) T0.3 is withdrawn —
it would have had to allow-list the one construct it exists to forbid, on the day it was
written. T0.3 is restated as an audit requirement instead: a conditional in a gated
package must have **both** branches walked: the web branch by the ratchet, the native
branch by a `control`, which resolves with io semantics. Without that second half the
ratchet reads green just as convincingly when the conditional was skipped and neither
branch was seen.

The construct remains discouraged, and the burden stays on the conditional: two real
implementations, a documented reason why one cannot serve both platforms, an injection
escape hatch, and a control. Anything short of that is the stub case, and D-1 still
refuses it.

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

**Strengthened by D-7.** Under dart2js the compiler catches *less* still — only
`dart:ffi` and `dart:mirrors` (§2.4). Choosing dart2js makes T0 more load-bearing, not
less.

### D-7 — dart2js is the compile target for the JS/TS artifact (2026-08-13)

The npm artifact described in [`js-api.md`](js-api.md) is built with `dart compile js`.
dart2wasm stays available at zero cost.

**Why.** The facade source is **identical** for both compilers — same
`dart:js_interop`, same `@JSExport`, same `.toJS` — so this is a packaging decision, not
a design one, and it is reversible. Measured on the same source, dart2js gives a single
77 KB file (24.5 KB gzipped) against dart2wasm's four files at ~25 KB gzipped: **size
parity**, plus universal browser support, trivial bundling, no CSP allowance, and correct
`is`/`as` on interop types. For a library that other people bundle, every remaining
factor favours dart2js. Precedent: Sass, the most-consumed Dart library on npm, ships
dart2js.

**Consequences that must not be lost** (detail in [`js-api.md`](js-api.md) §3):

- `dart:html` and `dart:js` stop being compiler-rejected, so "do not import them" becomes
  a **policy** enforced by [`acceptance.md`](acceptance.md) T0.1 rather than by the
  toolchain. It is kept in order to leave dart2wasm open.
- Open question C1 changes character: `cryptography`'s Web Crypto path becomes reachable
  under dart2js, which may remove the deferred Argon2id work
  ([`design.md`](design.md) §2.10).
- **Neutrality is unaffected.** `dart:io` compiles and then throws under *both*
  compilers (§2.4).

### D-8 — The JS facade lives in `at_client_web`; D-4 is not amended (2026-08-13)

No new Dart package. The facade sits at `packages/at_client_web/lib/src/js/` with its
entry point at `web/at_client_js.dart`, and the npm package is a build artifact
(compiled `.js` + hand-written `index.js`/`index.d.ts`), not a pub package.

**Why.** `dart compile js` compiles a *program*, so the facade is an entry point rather
than a library; packages ship entry points routinely. It is reachable only from that
`main()`, so it tree-shakes out of any Dart app importing `at_client_web` as a library —
Dart consumers pay nothing.

### D-9 — Keys cross the JS boundary as strings; events as callbacks (2026-08-13)

`AtKey` and `AtValue` are never materialised in JavaScript.

**Amended 2026-08-18.** As ruled 2026-08-13, keys crossed as the wire form
(`public:phone.wavi@bob`) because `AtKey` has no JSON codec — every codec in
`packages/at_commons/lib/src/keystore/at_key.dart` belongs to `Metadata` (`:627`/`:661`)
or `AppMetadata` (`:852`/`:862`) — and `AtKey.fromString` is lossy on metadata. **D-10
removes the flat plane those wire-form keys belonged to**, so the rationale changes: it is
no longer "keys cross as strings because they have no codec," it is **"no raw key plane is
exposed at all,"** codec or not. `AtKey`/`AtValue` remain excluded either way; the reason
is now structural rather than a workaround for a missing codec.

Separately, and unaffected by D-10/D-11: `Stream` has no JS bridge in any Dart SDK,
official or community, so every event surface is `subscribe(cb) → unsubscribe` — including
`AtCollection`'s eight stream-returning members (`js-api.md` §5.2 F-findings).

### D-10 — Collections are the sole JS/TS data plane; the flat plane is removed (2026-08-18)

The flat key/value plane specified in the original `js-api.md` §5.2
(`put`/`get`/`putBinary`/`getBinary`/`delete`/`exists`/`getKeys`/`getMeta`/`putMeta`) is
**removed** from the JS/TS surface, not deprecated in place. `AtCollection<T>`
(`packages/at_client/lib/src/collections/collections.dart`) is the sole data plane. A JS
consumer cannot address a raw protocol key.

**Why.** Two things changed since D-9 was ruled: `AtCollection<T>` shipped in `at_client`
3.12.0 (`df1272374`, 2026-04-27) as the supported successor to the deprecated
`at_collection/` tree, and it is JSON end-to-end — `CItem.toJson()` emits
`{'type', 'obj'}`, persisted with `jsonEncode` — so it costs nothing to bridge that the
flat plane's wire-string keys did not already cost. Retaining both would mean documenting
and testing two parallel data-access idioms for one protocol; retaining only the flat
plane would mean shipping the weaker, more Dart-specific API to the audience (JS/TS
developers) least equipped to work around it.

**Retained, not part of the flat plane removed:** `create`/`close` (lifecycle),
`waitUntilCaughtUp`/`isInSync` (`SyncService` — collections read a local synced store and
are silently stale without it), `notify`/`notificationStatus` (`NotificationService` —
sending to another atSign is not a collection write). See `js-api.md` §5.3.

**Cost, stated honestly.** A JS/Dart mixed fleet loses the ability to read/write arbitrary
protocol keys from JS. This is accepted because no consumer profile in `js-api.md` §0
(browser SPA, Node service, TS AI agent) has asked for raw key access — all three want
structured, typed records.

### D-11 — The Dart gear is typed via a declared `typeTag`; app types are never compiled into `at_client_web` (2026-08-18)

The JS and Dart gears mesh at exactly one point: the wire `typeTag`, a plain `String`.
Layer B (`plans/wasm/api-designing.md` §2.3) holds the machinery for declaring and
honouring tags; it never contains an app-specific collection type (`Todo`, `BlogPost`).

**Why.** Measured (§2.6 below): `_rehydrate` looks up factories by the tag stored on the
envelope (string-keyed, JS-compatible), but `_resolveType` stamps the write-side tag from
`obj.runtimeType` (a reified Dart `Type`, not JS-compatible). An untyped JS binding — one
`AtCollection<dynamic>` with TS generics as compile-time phantoms — would therefore write
every record under `type: 'n/a'`, making a JS client and a Dart client unable to share a
collection as equals. That is a product defect, not a binding nicety, so the untyped
design is rejected in favour of a facade that requires a declared tag per collection.

**Cost, stated honestly, and left open.** Honouring a declared tag on writes requires
overriding `_resolveType`, which upstream does not expose today. Until an additive
`writeTypeTag` ships upstream (preferred) or the facade adopts a bounded carrier-class
shim (fallback, verified mechanically viable via `CItem.toJson()`/`jsonEncode`), **the JS
surface is read-compatible with typed Dart peers but not write-compatible.** See
`js-api.md` §11 JS-7 and §5.2.

**Bound.** Compiling app types into `at_client_web` — even as an opt-in — is rejected
outright: it would force every JS app into a Dart build step, destroying the
`npm install` story this entire project exists to deliver.

### D-12 — Client storage is one injected bundle, and it owns the sync queue (2026-09-05)

`at_client` gains a storage abstraction of its own: a single object owning **both** the
local keystore and the sync queue. This supersedes [§2.3](design.md#23-the-sync-queue)'s
design of a separate spec interface for the queue, and S3 with it. Three implementations
are in scope — the Hive-backed default, a SQLite-backed one, and an in-memory one that
touches no disk at all.

The abstraction is `at_client`'s, not an extension of `at_persistence_secondary_server`'s
`AtPersistenceBundle`. That package is owned by `at_server` and reaches this tree through
a `dependency_overrides` git ref, so extending it would mean a coordinated cross-repo
change and a publish before `at_client` could depend on the result.

**Why one bundle rather than two interfaces.** The keystore and the queue choose their
storage independently today, under two different keys, and neither key is the principal.
The keystore goes through `StorageManager` to `_factory.initialize(atSign, path)`; the
queue reads `preference.hiveStoragePath` and, when it is null, opens on the **global**
Hive instance under a box named from the atSign alone. The null case is exactly the
injected-keystore case, so a caller that injects a store today gets an isolated keystore
and a silently *shared* queue — and an "in-memory" store that still writes a Hive box to
disk. One owner makes both unrepresentable rather than guarded against.

**Ownership and lifetime.** The bundle refuses a second opener: ownership is enforced
inside the bundle rather than by a registry `at_client` keeps, so a backend cannot forget
the check and bundles `at_client` never sees are covered too. The claim is released when
the client closes, and `stop()` is what releases it.

**What this resolves.** [OQ-3](#5-open-questions), for storage: the capability hangs off a
factory rather than `AtClientPreference`. `AtClientPreference.hiveStoragePath` is
deprecated in this major, its successor being a bundle injected through a new static
factory on `AtClient` — which builds *and* wires, closing by construction the hole where a
client came back with its service getters throwing. Deprecating `AtClientManager` is the
direction of travel; where its `AtSignChangeListener` capability goes is deferred, because
that capability exists only to announce that a global current atSign changed.

**Surface (ruled 2026-09-05).** The owner of a claim is the client object, compared by
identity — not the instance key, which for a legacy client is the bare atSign and so cannot
tell two legacy clients of one atSign apart. Owned storage is closed on release; injected
storage is only detached, the client knowing which it has. After detach, only the same
principal may re-attach until `clear()` runs — the bundle remembers who held it last, so a
different enrollment cannot inherit records it cannot decrypt and pushes it cannot make.
A deliberate hand-over is `forgetPrincipal()`, which lifts the last-holder guard while keeping
every record;
`clear()` empties keystore and queue together and forgets the principal too, so a
half-cleared store is unrepresentable and getting past the guard never costs the records. The surface is in
[`design.md`](design.md#22-storage-bootstrap) §2.2.

**Cost, stated honestly.** `stop()` is the atSign-switch-away path, so releasing storage
there means switching back reopens a cold store and pulls again. That is accepted. It is
not free: a cold store is precisely the condition under which a local-first write followed
by a read routed to the atServer loses the race, which is how this was found. `start()`
does not rebuild what `stop()` nulls, so a stopped client must never be handed back. The
manager's same-atSign short-circuit already refuses one, and nothing else in production
reaches a cached client; X1 pins that guard before X4 changes `stop()`, since the guard is
what a released client's safety then rests on. (Amended 2026-09-05: first written as "two
paths hand back a stopped client" — one was already guarded, the other has no caller.)

### D-13 — Local storage is isolated per (atSign, enrollmentId), not per atSign (2026-09-05)

A client's local keystore and sync queue are keyed by the **enrollment**, not by the
atSign alone. Two enrollments of one atSign on one device get **separate** stores.

**Why.** An enrollment holds key material only for its granted namespaces; a scoped
enrollment and a differently-scoped one on the same atSign hold different secrets and see
different records. Sharing a store between them would hand one enrollment records and
pending writes belonging to another's scope — the very boundary
[D-12](#d-12--client-storage-is-one-injected-bundle-and-it-owns-the-sync-queue-2026-09-05)'s
claim exists to keep. Storage granularity must match the enrolled principal — the
`(atSign, enrollmentId)` pair the instance cache keys on — not the atSign. (This is a
different sense of "principal" from D-12's, which names the *claim holder* as the client
OBJECT by identity; here it is the *storage-identity* granularity. Two senses, one word —
qualify at each use.)

**The defect this names.** Today storage is keyed by the atSign alone, a survival of the
one-client-per-atSign era: the keystore box is `sha256(atSign)`, the sync-queue box is
`syncqueue_<sha256(atSign)>`, and `AtClientImpl` takes `preference.hiveStoragePath`
verbatim — nothing derives a per-enrollment location. Two enrollments handed the same
path therefore share one box; on the global Hive instance they are literally one store.
`HiveInstances.forPath(path)` isolates by *path*, but nothing makes two enrollments *use*
different paths, and the per-atSign "refuse the second client" guard built during X4
merely hid the collision rather than isolating the data.

**Open — the isolation key.** Two routes, undecided:
- **Per-enrollment location:** `at_client` derives `<hiveStoragePath>/<enrollmentId>` (its
  own Hive instance per enrollment). No upstream change; box names stay `sha(atSign)`;
  isolation is by directory.
- **Enrollment in the box name:** `sha(atSign|enrollmentId)`. Cleaner identity, but the
  keystore box name lives in `at_persistence_secondary_server` (at_server) — a cross-repo
  change and a migration for existing atSign-named boxes.
A legacy client (no enrollmentId, or the `primary` enrollment) should keep today's
atSign-only location either way, so existing single-enrollment installs are not migrated.

**Consequences for X4.** The release semantics (`stop()` releases storage) are sound and
become *safe* once storage is per-enrollment: no sibling shares a client's box, so closing
on release cannot pull the store out from under another enrollment or an in-flight sync
round. The per-atSign guard comes out — it is the wrong shape. PR #2208 (the release half)
is paused behind this ruling; its release code is kept, its guard reworked.

---

## 2. Measured findings

All measured on **Dart SDK 3.12.0 (stable)**, Linux x64, 2026-08-13. These are
toolchain behaviours, not specification guarantees — re-measure on SDK upgrade. Method
and output in [`acceptance.md`](acceptance.md) §1.

### 2.1 dart2wasm accepts `dart:io` and `dart:isolate`

| Library        | `dart compile wasm` |
| -------------- | ------------------- |
| `dart:io`      | compiles, exit 0    |
| `dart:isolate` | compiles, exit 0    |
| `dart:ffi`     | rejected            |
| `dart:html`    | rejected            |
| `dart:js`      | rejected            |
| `dart:mirrors` | rejected            |

### 2.2 The `dart:io` stub throws on first use

The module from §2.1 was executed under Node 24.18.0 and threw
`Unsupported operation: _Namespace` at the first `File.existsSync()`. The failure mode
is exactly **compiles clean, throws at runtime**.

### 2.3 A runtime gate is available today without a browser

`dart test -p node -c dart2wasm` runs green, including an assertion that
`dart.library.io` is false. This was the reason T2 could be specified as a gate rather
than as an aspiration. The "zero-infrastructure CI addition" this section originally
claimed did not survive contact with a hosted runner — see §2.7.

`dart test -p chrome -c dart2wasm` compiles the module correctly but was **not observed
executing** — no Chrome binary in the development environment. T3 must be validated on
its first CI run.

### 2.4 dart2js is blind to `dart:io` too, and permits more besides

Same probes, run through `dart compile js`:

| Library           | dart2js      | dart2wasm |
| ----------------- | ------------ | --------- |
| `dart:io`         | compiles     | compiles  |
| `dart:isolate`    | compiles     | compiles  |
| `dart:html`       | **compiles** | rejected  |
| `dart:js`         | **compiles** | rejected  |
| `dart:js_interop` | compiles     | compiles  |
| `dart:ffi`        | rejected     | rejected  |
| `dart:mirrors`    | rejected     | rejected  |

dart2js emits the same `_Namespace` throwing stub for `dart:io`. So **no Dart web
compiler gates `dart:io`** — switching targets buys no protection, and D-6 holds
regardless of D-7.

### 2.5 The JS/TS language boundary

Measured with `@JSExport` + `createJSInteropWrapper`, called from Node 24.18.0. Full
tables in [`js-api.md`](js-api.md) §1. The load-bearing results:

- **Nothing converts automatically** — `Future`, `Stream`, `List<T>`, `Uint8List` and
  custom classes all cross as opaque Dart handles.
- **An unconverted `Future` completing with an error killed the Node process** — no
  rejection, no catch. This is why [`acceptance.md`](acceptance.md) T6 gates on it.
- **Hand-adapted signatures work**: `JSPromise<JSString>` and friends yield real strings,
  a real `Uint8Array`, a real `Array`, and catchable rejections.
- **JavaScript objects can satisfy Dart interfaces** — a JS `{read, write}` was used
  behind a Dart `abstract interface class`. This is what lets TypeScript supply platform
  implementations, and is why Node needs no Dart package of its own.
- **dart2js on Node hangs silently without `globalThis.self = globalThis`** — Node has
  neither `self` nor `MutationObserver`, so Dart's microtask scheduler never runs and
  every Promise stays pending. No error is raised.

### 2.6 The collections API's write/read asymmetry (2026-08-18)

Measured against `packages/at_client/lib/src/collections/collections.dart` at HEAD. Drives
D-10/D-11 and `js-api.md` §5. **✓** = re-grepped at plan time; two line numbers reported by
initial exploration disagreed (`wherePath` at both `:3486` and `:4486`) — `:3486` is
confirmed correct and is the only one recorded below.

| # | Finding | Consequence |
| --- | --- | --- |
| F1 | Omitting **both** `fromJson` and `typeTag` is supported — `AtClient.collection()`'s pairing check (`:581-596`) fires only on an XOR. Precedent: `example/bin/collections_primitives.dart:18-27` uses `AtCollection<Map>` with neither. | Untyped binding is *possible*. D-11 declines it in favour of a declared-tag design — see F3. |
| F2 | **Read path is string-keyed.** `_rehydrate` (`:3033-3062`) looks up `_factoriesByTag[type]` from the tag on the stored envelope. Unknown tag → one `_logger.warning` + raw cast, **no throw**. | Reads degrade gracefully; a JS collection can read data written by a typed Dart peer. `CItem.type` (`:4726`) is the discriminator. |
| F3 | **Write path is `Type`-keyed.** `_resolveType` (`:2960` ✓) does `_factoriesByType[obj.runtimeType]`; anything unregistered stamps `'n/a'`. | **The finding D-11 is built on.** An untyped JS binding cannot write a meaningful type tag — a JS and Dart client cannot share a collection as equals without an additive change. |
| F4 | The `Predicate` AST is introspectable but **not serializable** — no `toJson`/`fromJson`, `CmpPredicate._` is private (`:4261`), `PathField.extract` is a live Dart closure (`path` is metadata only, `:4151-4155`). | A path-based query DSL must be built in Layer B (pure Dart), not bound directly — JS gets `.where(path, op, value)`, never the AST. |
| F5 | `PredicateOp` has 13 members (`:4204-4218` ✓); `like`/`inSet`/`between`/`contains`/`startsWith` throw `UnimplementedError` (`:4305-4307` ✓). | Must never appear in the `.d.ts` as working — `js-api.md` §9. |
| F6 | `Atsign` is `extension type Atsign._(String)` — **erased to `String` at runtime** (`at_commons-5.9.0/lib/atsign.dart:6`). `toAtsign()` normalises (lowercase, prepend `@`, strip right-side dots) and throws `InvalidAtSignException`. | No JS wrapper type needed, but normalisation must route through Dart or keys mismatch silently. |
| F7 | **No `dispose()` on `AtCollection`.** Fields at `:439`/`:447` say "Held so a future `dispose()` can cancel cleanly"; `availableEvents`' scheduler runs for the collection's lifetime (`:2786-2788`). | The facade must rely on the `(namespace, eventSource)` cache (`at_client_impl.dart:256`) rather than constructing per JS object — bounds, does not eliminate, a subscription leak. |
| F8 | `CEvent` is deliberately **not sealed** (`:5077`) — new subtypes ship in minors. | The JS discriminated union needs a default/unknown branch, permanently. |
| F9 | Collections code has zero direct `dart:io`, but requires `AtClient`, and `at_client_spec.dart:1` imports `dart:io`. | Not a new blocker — exactly what Phases 1–5 exist to remove. |
| F10 | `orderBy` (`:3496` ✓) and `thenBy` (`:3521` ✓) take `Comparable Function(CItem<T>)` closures. **No path-based ordering variant exists upstream.** | Any `orderByPath` in the facade is a Layer B invention that must be labelled as such, not attributed to upstream. |
| F11 | `SubSpec` is `const`-constructible but its only opener is `_openOnForTest` (`collections_test_hooks.dart:168`, `@visibleForTesting`, **not exported** from the barrel). | `watchWithTree` is unbindable today — `js-api.md` §9 excludes it, blocked on an upstream export rather than a design choice. |
| F12 | `CItem.toJson()` emits `{'type', 'obj'}` and the caller `jsonEncode`s it (`:4809`, `:1088` ✓); `jsonEncode` invokes `toJson()` on a non-primitive payload. | Confirms the carrier-class shim (D-11's fallback route) is mechanically viable, bounded by a fixed ceiling of concurrent tags per isolate. |

**Stability, both readings recorded.** `AtCollection`'s class doc (`:58-62`) declares
*"Status: stable"* and names its compatibility mechanisms (`interface class` modifier,
`final` event subclasses, pre-allocated enum slack); there is no `@experimental`. Against
that: the API is roughly four months old (born `df1272374`, 2026-04-27), took a breaking
change 2 days after introduction (`fb4c96587`, mandatory `typeTag`), reworked
`EventSource` semantics since, ships 7 correctness fixes in the current 3.14.1, and has
**zero functional/e2e coverage** — all 209 tests in `packages/at_client/test/` are
mocktail unit tests against `MockAtClient`; nothing in `tests/at_functional_test/` or
`tests/at_end2end_test/` references it. `js-api.md` §10 marks the JS-side collections
surface unstable/0.x on this basis — attributed to the gap in *this project's* boundary
validation, not to a dispute of upstream's stability contract.

### 2.7 T2 runs locally and cannot run on a hosted runner (2026-08-27)

Measured while wiring Phase 0's CI jobs.

**The blocker.** On GitHub's `ubuntu-latest`, every `dart test -p node -c dart2wasm`
suite fails to load before any test body executes: the CJS bootstrap calls `instantiate`
from the ESM `.mjs` init file and receives `undefined`. The identical command passes on
Dart 3.12 + Node 24 locally. Neither version is pinned in
`.github/workflows/at_libraries.yaml`, so a failure in CI would be reporting a toolchain
mismatch rather than anything about this codebase — which is why T2 is absent from CI
rather than present and allowed-to-fail. An allowed-to-fail job that has never once passed
teaches a reader to ignore it.

**Two mechanics for whoever pins the pair.** `dart2wasm` emits one wasm module per test
*file*, so `--concurrency=1` is the wrong lever — it serialises the compilations that
dominate the wall clock without reducing the module count. And `Uri.base` throws under
dart2wasm on Node; code reachable from a suite cannot read it.

**What this does not say.** Nothing about whether our code is correct under WasmGC. The
suites that ran locally are evidence for the paths they touch; the gap between that and
CI is a scheduling fact, not a finding.

---

## 3. Superseded positions

| Position in `plan.md`                                                                                   | Status                                                                                              |
| ------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------- |
| "No `dart:io`. The compiler hard-errors if any *reachable* code transitively imports it." (§1)          | **False on Dart 3.12** — §2.1. Superseded by D-6.                                                   |
| "Isolates are experimental under dart2wasm" (§1)                                                        | Incomplete — `dart:isolate` compiles without complaint, so the compiler gives no signal either way. |
| "Use **conditional imports** … plus the injection seams" (§4, packaging strategy)                       | Superseded by D-1.                                                                                  |
| "One set of core packages … platform differences live behind conditional imports" (Goal 2)              | Superseded by D-1 / D-5. The packages stay single-sourced; the mechanism changes.                   |
| "No regression on native. Every conditional seam keeps the existing native path byte-for-byte" (Goal 3) | Narrowed by D-3 to a behavioural commitment.                                                        |
| Gates A1/A2 (`dart compile wasm`) as the leading acceptance criteria                                    | Demoted to T1 by D-6.                                                                               |
| Tasks I4–I8 (the `at_auth` sweep)                                                                       | Removed — owned by the PQ program's S-5/S-6.                                                        |

The predecessor `plan.md` is deleted rather than left in place, because its §1
constraint table and its A1/A2 gates are actively misleading. It remains in git history at
`d3e7dcdd5`, the commit that added it. The material worth keeping — the persistence
analysis, the `sqlite3` compile validation, the storage-backend comparison, the B-series
browser gates — is carried into [`design.md`](design.md) and
[`acceptance.md`](acceptance.md).

The file was still present until 2026-08-27, despite this section having asserted its
deletion since 2026-08-13, and the `33a062a61` named here as the recovery point is the
trunk commit the plan was *written against* — it never held the file.

### Positions from *this* doc set that have since been withdrawn

| Position                                                                                       | Status                                                                                                                         |
| ---------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------ |
| T0.2's **two-way** ratchet — a loosened baseline fails and demands an edit                     | Shipped **one-way**. A fix passes with no edit here; only tightening ever requires one. [`acceptance.md`](acceptance.md) T0.2. |
| T0.3's ban on `if (dart.library.` in a neutral `lib/`                                          | Withdrawn — D-1's amendment above. Restated as: both branches of a conditional must be walked.                                 |
| R5 — add the `dart test -p node -c dart2wasm` matrix dimension, allowed-to-fail                | Withdrawn. The hosted runner cannot load a suite at all; waits on a pinned Dart/Node pair. §2.7.                               |
| R1's plan to lift `packages/at_auth/test/wasm/dep_tree_test.dart` into a shared *test* utility | Shipped as a standalone CLI, `tools/wasm_shakedown`, run as its own CI job rather than as a per-package test.                  |

**Resolved.** A prior merge-time follow-up here tracked four references to
`docs/projects/wasm/plan.md` on the `at_client_sdk-atauth-wasm` branch. None reached trunk:
`at_auth_web.dart` and `test/wasm/` were never landed, at_auth 4.0.0-rc1 shipped
`at_auth_io.dart` and `wasm_barrel_test.dart` instead, and no reference to the deleted
`plan.md` survives anywhere outside this directory.

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

**OQ-1 — Does `at_auth` ship a conditional default or a removed one? RESOLVED
2026-08-27: both, on different axes.** at_auth 4.0.0-rc1 shipped the *removed* default
where the question was originally asked — `FileAtKeysIo` is gone from `at_auth.dart`, and
the filesystem, raw-socket and `dart:io` HTTP code moved to `at_auth_io.dart`. It also
shipped one *conditional* default the prototype did not have: the reachability probe in
`probe_default.dart`. Neither the prototype's `src/io/defaults_stub.dart` nor
`at_auth_web.dart` exists on trunk.

So the inconsistency this question raised is settled, and not by either of the two answers
it offered. The ruling is recorded against D-1 above: the conditional stands on the
narrow ground that both of its branches are real, and it costs T0.3 its ban.

**OQ-2 — Do the `_io` barrels ship in the same major as the interface change, or one
release ahead?** Shipping the barrel first lets consumers migrate their imports before
the default disappears, turning one hard break into two soft steps. Shipping together
is one release instead of two. Decide per package at execution time.

**OQ-3 — Where do platform capabilities hang: `AtClientPreference` or
`AtServiceFactory`?** `AtServiceFactory` (`at_client_manager.dart:265`) is the closer
analogue and already has real overrides; `AtClientPreference` is what callers already
touch and already carries `CryptoConfig` as precedent. See
[`design.md`](design.md) §4. **Resolved for storage by D-12** — a bundle injected through
a static factory on `AtClient`, not a preference field. Open for the remaining
capabilities.

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

**OQ-10 — Does `package:hive`'s stub resolve under *dart2js*?** OQ-9 asks this for
dart2wasm, where `dart.library.html` is false. Under dart2js it is **true**, so Hive may
resolve to its real IndexedDB backend rather than the no-op stub — a different outcome,
and possibly a working one. Re-ask against D-7's target before acting on OQ-9.

The JS/TS-surface questions (**JS-1..JS-8** — `cryptography`'s path under dart2js,
whether `AtCollection` is exposed (JS-2, **resolved** 2026-08-18 — see D-10), whether to
ship a dart2wasm build too, whether `at_client_web` keeps both jobs, who owns the npm
release, throw-vs-return-tuple for the error surface, upstream `writeTypeTag` vs. a
carrier-class shim for write-compatibility (JS-7), and the `AtClientManager` singleton
blocking multi-instance JS clients (JS-8)) live in [`js-api.md`](js-api.md) §11.

**Answered.** *Does `package:sqlite3`'s web entry point compile under dart2wasm?*
**Yes** — Dart 3.11.3, `sqlite3` 2.9.4, with a negative control that failed as
required. [`design.md`](design.md) §0.2. Runtime behaviour remains unproven and is
covered by T3.1 and X1. Note D-7 makes this the *less* critical of the two paths:
`package:sqlite3`'s web support was originally built for dart2js.

---

## 6. Decision log

| Date       | Entry                                                                                                                                                                                               |
| ---------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 2026-08-03 | Predecessor `plan.md` written against `33a062a61` by gkc. `package:sqlite3` web compile validated.                                                                                                  |
| 2026-08-12 | `at_client_sdk-atauth-wasm` worktree prototypes the at_auth barrel split and the dependency-tree walk; its `dep_tree_test.dart` header records that dart2wasm does not reject `dart:io`.            |
| 2026-08-13 | Measured and confirmed the dart2wasm library-acceptance matrix (§2.1), the runtime throw (§2.2), and the browser-free test gate (§2.3).                                                             |
| 2026-08-13 | **D-1..D-6 ruled.** Injection over conditional imports; no throwing stubs; breaking majors accepted; `at_client_web` the only new package; `_io` barrels for native; structural gate primary.       |
| 2026-08-13 | Doc set split five ways on the `docs/projects/pq` convention; `plan.md` deleted.                                                                                                                    |
| 2026-08-13 | Corrected the `at_server_status` "unused import" claim and the `at_client_flutter` "platform implementer" framing (§4).                                                                             |
| 2026-08-13 | Ceded `at_auth` to the PQ program's S-5/S-6; tasks I4–I8 removed from this backlog.                                                                                                                 |
| 2026-08-13 | Measured the JS/TS language boundary (§2.5) and the dart2js library matrix (§2.4); confirmed no Dart web compiler gates `dart:io`.                                                                  |
| 2026-08-13 | **D-7..D-9 ruled.** dart2js is the JS/TS compile target; the facade lives in `at_client_web` with D-4 unamended; keys cross as strings and events as callbacks. `js-api.md` added as the sixth doc. |
| 2026-08-18 | Added JS-6 (throw vs. return-tuple, supabase-js precedent) to `js-api.md` §11. |
| 2026-09-05 | **D-12 ruled.** Client storage becomes one injected bundle owning the keystore and the sync queue; S3 and §2.3's separate queue interface are superseded. `hiveStoragePath` deprecated; `stop()` releases storage. OQ-3 resolved for storage. |
| 2026-09-05 | **D-13 ruled.** Local storage is isolated per (atSign, enrollmentId), not per atSign — a scoped enrollment's data must not share a store with another scope. Names the atSign-only box-key defect; the isolation key (per-enrollment path vs box name) is open. PR #2208 paused. |
| 2026-08-18 | `plans/wasm/api-designing.md` written: the three-layer Dart facade split (Layer A/B/C) and the Axis A/B/C reference-SDK survey. `plans/wasm/key-storage.md` written, depending on the split. |
| 2026-08-18 | Measured the collections API's write/read asymmetry (§2.6, F1–F12) against `packages/at_client/lib/src/collections/collections.dart`. |
| 2026-08-18 | **D-9 amended, D-10 and D-11 ruled.** Collections (`AtCollection<T>`) become the sole JS/TS data plane; the flat key/value plane from the original §5.2 is removed, not deprecated in place. The Dart gear is typed via a declared `typeTag`; app types are never compiled into `at_client_web`. Write-compatibility with typed Dart peers is left open pending an upstream `writeTypeTag` or a bounded carrier-class shim (JS-7). `js-api.md` §5–§11 rewritten to match; `plans/wasm/api-designing.md` §2.3/§2.4/§2.6 rewritten for the collections-shaped Layer B. JS-2 resolved; JS-8 (the `AtClientManager` singleton blocking multi-instance clients) recorded. |
| 2026-08-24 | **Phase 0 landed** ([#2149](https://github.com/atsign-foundation/at_client_sdk/pull/2149)). The dependency-tree walk ships as `tools/wasm_shakedown` — a standalone CLI with its own test suite, not a per-package test as R1 specified — wired into `.github/workflows/at_libraries.yaml` as a hard gate. `at_chops` gated first. |
| 2026-08-25 | at_auth 4.0.0-rc1 ([#2179](https://github.com/atsign-foundation/at_client_sdk/pull/2179)), the PQ program's S-5: the `at_auth_io.dart` barrel split, `FileAtKeysIo` default dropped, registrar onto `package:http`. Ships one conditional export (`probe_default.dart`). |
| 2026-08-27 | **Phase 0 matured** ([#2183](https://github.com/atsign-foundation/at_client_sdk/pull/2183)). Gate config extracted to `.github/wasm_gates.yaml`; `controls` made mandatory; `at_auth` gated. **T0.2's two-way ratchet withdrawn** for one-way baselines, **T0.3's no-conditionals ban withdrawn** and restated as a both-branches-walked requirement (D-1 amended, OQ-1 resolved), **R5 withdrawn** — T2 cannot run on a hosted runner (§2.7). T0.4 remains unimplemented. |
| 2026-08-27 | Phase 1 in review as a three-PR stack: [#2162](https://github.com/atsign-foundation/at_client_sdk/pull/2162) (S4–S6) ready, [#2163](https://github.com/atsign-foundation/at_client_sdk/pull/2163) (S1, S2) and [#2164](https://github.com/atsign-foundation/at_client_sdk/pull/2164) (S3) draft. `plan.md` deleted, as §3 had asserted since 2026-08-13. |
