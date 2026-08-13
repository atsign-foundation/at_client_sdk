# js-api.md — Consuming `AtClient` from JavaScript and TypeScript

**Status:** design doc (proposed). Lives in `docs/projects/wasm/`.
**Purpose:** how a JavaScript or TypeScript application consumes the browser-capable
`AtClient` — the compile target, the API surface, what the language boundary forces on
that surface, and what is deliberately excluded.
**Lane:** this doc owns *the non-Dart consumer story*. For the neutrality thesis see
[`roadmap.md`](roadmap.md); for the internal seams see [`design.md`](design.md); for
sequencing see [`implementation-plan.md`](implementation-plan.md); for the gates see
[`acceptance.md`](acceptance.md); for the rulings see [`decisions.md`](decisions.md).
**Measured against:** Dart SDK 3.12.0 (stable), Node 24.18.0, 2026-08-13.

## Table of contents

- [0. Why this doc exists](#0-why-this-doc-exists)
- [1. The measured boundary](#1-the-measured-boundary)
- [2. Compile target: dart2js](#2-compile-target-dart2js)
- [3. What choosing dart2js changes upstream](#3-what-choosing-dart2js-changes-upstream)
- [4. Where the facade lives](#4-where-the-facade-lives)
- [5. The TypeScript surface](#5-the-typescript-surface)
- [6. Error mapping](#6-error-mapping)
- [7. TypeScript-supplied implementations, and Node](#7-typescript-supplied-implementations-and-node)
- [8. npm packaging](#8-npm-packaging)
- [9. Deliberately excluded](#9-deliberately-excluded)
- [10. Risks](#10-risks)
- [11. Open questions](#11-open-questions)

---

## 0. Why this doc exists

The rest of this project makes `at_client` implementation-neutral so it runs in a
browser. Every other doc assumes the *consumer* is a Dart program: `at_client_web` is
"platform glue, playing the role `at_client_flutter` plays for mobile — app authors
depend on this."

That leaves the obvious next question unanswered. A React app, a Node service, or a
TypeScript MCP server cannot depend on a pub package. This doc specifies what they
depend on instead.

**Consumer profiles**, and what actually differs between them:

| Consumer                                | Transport                     | Storage                                                        | Notes                                                                                                 |
| --------------------------------------- | ----------------------------- | -------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------- |
| Browser SPA (React/Vue/Svelte, bundled) | `WebSocket`                   | IndexedDB / SQLite-wasm, Dart-side                             | The primary target.                                                                                   |
| Node service                            | `WebSocket` (Node 22+ global) | **Must be supplied from TypeScript** — Node has no `indexedDB` | Also needs the loader shim in [§7](#7-typescript-supplied-implementations-and-node).                  |
| TypeScript AI agent / MCP server        | as Node                       | as Node                                                        | Wants the flattest possible surface; favours [§5](#5-the-typescript-surface) over the collection API. |

Storage is the only real fork. Transport, connectivity and crypto are identical across
all three.

---

## 1. The measured boundary

Everything in this section was measured directly, not taken from documentation. It is
the reason the surface in [§5](#5-the-typescript-surface) looks the way it does.

### 1.1 Almost nothing converts automatically

A Dart class annotated `@JSExport` and installed with `createJSInteropWrapper` exposes
its instance methods as own properties on a plain JS object. What those methods *return*
is the problem:

| Dart return type        | What JavaScript receives                                    |
| ----------------------- | ----------------------------------------------------------- |
| `String`, `int`, `bool` | Correct JS primitive                                        |
| `Future<T>`             | **Opaque Dart handle** — not a thenable; `await` is a no-op |
| `Stream<T>`             | **Opaque Dart handle**                                      |
| `List<T>`               | **Opaque Dart handle**                                      |
| `Uint8List`             | **Opaque Dart handle**                                      |
| Custom Dart class       | **Opaque Dart handle**                                      |

### 1.2 The failure mode is a process kill, not a type error

An unconverted `Future` that completes with an *error* does not reject. It surfaced as an
uncaught exception that **terminated the Node process**.

This is the same defect class the neutrality programme exists to eliminate — compiles
clean, dies at runtime — reappearing one layer up. It is why
[`acceptance.md`](acceptance.md) T6 gates on it explicitly.

### 1.3 Hand-adapted signatures work correctly

Rewriting each method to return `JSPromise<JSString>`, `JSPromise<JSUint8Array>`,
`JSPromise<JSArray<JSString>>` and so on produces exactly what a JS caller expects: real
strings, a real `Uint8Array`, a real `Array`, real `null`, and catchable rejections.

`Future<T>.toJS` requires **`T extends JSAny?`**, so `Future<String>` and
`Future<List<String>>` have no `.toJS` — each must be mapped first. **Every async method
carries this tax.** It is the single largest cost in the facade, and it cannot be
generated from the existing Dart API.

### 1.4 `Stream` has no bridge

There is no `Stream.toJS`, no `JSAsyncIterable`, and no community package supplying one.
`dart:js_interop` gained `JSIterable`/`JSIterator` in Dart 3.12, but the CHANGELOG
describes them as modelling the **synchronous** iteration protocol only.

The working translation is a callback subscription returning an unsubscribe function —
measured delivering events and cancelling cleanly:

```dart
JSFunction subscribe(JSFunction onEvent) { … return (() => sub.cancel()).toJS; }
```

### 1.5 JavaScript can implement a Dart interface

A plain JS object with `async read(k)` / `async write(k, v)` was adapted behind a Dart
`abstract interface class` and used by Dart code, which awaited into JavaScript
correctly.

**This is the most consequential finding in this doc.** The injection seams
[`design.md`](design.md) is already building — `AtTransport`, the storage factory,
`AtKeysIo` — can be satisfied *from TypeScript*. It is what lets one artifact serve both
the browser and Node ([§7](#7-typescript-supplied-implementations-and-node)).

---

## 2. Compile target: dart2js

**Ruling: the JS/TS artifact is built with `dart compile js`.** Recorded in
[`decisions.md`](decisions.md) D-7.

The facade source is **identical** for both compilers — same `dart:js_interop`, same
`@JSExport`, same `.toJS`. So this is a packaging decision, not a design one, and it is
reversible at any time for zero source cost.

Measured by compiling the same facade both ways:

|                              | **dart2js**                                                                             | dart2wasm                                                                                |
| ---------------------------- | --------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------- |
| Output                       | **1 file**, 77 KB (**24.5 KB gz**)                                                      | 4 files: 52.7 KB `.wasm` + 13.4 KB `.mjs` + `.wasm.map` + 79 B `.support.js` (~25 KB gz) |
| Loading                      | `require` / `<script>`; runs `main()` on load                                           | fetch → `compile` → `instantiate` → `invoke`                                             |
| Bundlers                     | **trivial — it is just JavaScript**                                                     | manual `.wasm` asset handling, per bundler                                               |
| Browsers                     | **universal**                                                                           | Chrome 119+ / Firefox 120+ / Safari 18.2+                                                |
| CSP                          | **nothing special**                                                                     | requires `script-src 'wasm-unsafe-eval'`                                                 |
| Node                         | works; needs the shim in [§7](#7-typescript-supplied-implementations-and-node)          | works unmodified                                                                         |
| `is` / `as` on interop types | **correct**                                                                             | **broken** — all interop types share one `externref` representation                      |
| Promises                     | **real native `Promise`**                                                               | `JSPromise` (also awaitable)                                                             |
| Arrays                       | carry a harmless `Symbol($ti)`; `Array.isArray`, spread and `JSON.stringify` all behave | clean                                                                                    |

**Size parity is the headline.** dart2wasm's advantage does not materialise at this
scale — 24.5 KB vs ~25 KB gzipped. Dart's own performance claim is qualified to *"large
applications using deferred loading"*, which a library is not. Every other row favours
dart2js for something other people bundle.

Precedent: **Sass** — the most-consumed Dart library on npm — ships dart2js, recently
enough for it to be a deliberate choice rather than legacy.

Under dart2js the facade behaved identically to dart2wasm across the whole probe: real
`Promise`s, a real `Uint8Array`, `Array.isArray` true, catchable rejections carrying the
same message, working subscribe/unsubscribe, process survives.

---

## 3. What choosing dart2js changes upstream

dart2js relaxes constraints that the rest of this doc set treats as absolute. Recording
that here rather than letting it erode silently.

**Measured library-acceptance matrix:**

| Library           | dart2js      | dart2wasm |
| ----------------- | ------------ | --------- |
| `dart:io`         | compiles     | compiles  |
| `dart:isolate`    | compiles     | compiles  |
| `dart:html`       | **compiles** | rejected  |
| `dart:js`         | **compiles** | rejected  |
| `dart:js_interop` | compiles     | compiles  |
| `dart:ffi`        | rejected     | rejected  |
| `dart:mirrors`    | rejected     | rejected  |

1. **The compile gate gets weaker still.** Under dart2js, T1 catches only `dart:ffi`
   (and `dart:mirrors`, which this codebase does not use). [`decisions.md`](decisions.md)
   D-6 already ranks the structural T0 gate above the compiler; dart2js makes that ruling
   *more* load-bearing, not less.
2. **"No `dart:html` / `dart:js`" becomes self-imposed.** Under dart2wasm it was
   compiler-enforced. Under dart2js it is a policy kept in order to leave dart2wasm open
   — so it moves into [`acceptance.md`](acceptance.md) T0.1 as an explicit rule.
3. **`cryptography`'s Web Crypto path becomes reachable.** Open question C1 exists
   because `cryptography` 2.x's browser path uses `dart:html`, which dart2wasm rejects.
   Under dart2js that path *works*. The question changes from "will it compile?" to
   "which path does it select, and is it faster?" — and a Web Crypto-backed Argon2id and
   AES could remove the deferred performance work entirely. See
   [§11](#11-open-questions).
4. **Storage gets safer, not riskier.** `package:sqlite3`'s web support was originally
   built for dart2js — `common.dart` documents interfaces implemented by "the `dart:ffi`
   and the `dart:js` WASM version". The validated dart2wasm compile was the *less*
   proven of the two paths.

**Nothing here weakens the neutrality work.** `dart:io` compiles and then throws under
**both** compilers — dart2js emits the same `_Namespace` stub. The neutrality programme
is required either way, and T0 is compiler-independent. *The neutrality work is the
product; the compiler is a packaging decision.*

---

## 4. Where the facade lives

**Inside `at_client_web`.** No new Dart package;
[`decisions.md`](decisions.md) D-4 stands unamended.

1. **The npm package is not a Dart package.** It is a build artifact — the compiled
   `.js`, a hand-written `index.js` wrapper, and a hand-written `index.d.ts`. Publishing
   to npm implies no pub package.
2. **The facade is an entry point, not a library.** `dart compile js` compiles a
   *program*. The facade only exists because a `main()` calls `createJSInteropWrapper`
   and installs the result. Packages ship entry points routinely without being split.
3. **Dart consumers do not pay for it.** The facade is reachable only from that entry
   point's `main()`, so it tree-shakes out of any Dart application that imports
   `at_client_web` as a library.

```
packages/at_client_web/
  lib/at_client_web.dart        # Dart-facing platform impls — unchanged by this doc
  lib/src/js/                   # the @JSExport facade, marshalling, error mapping
  web/at_client_js.dart         # main() that installs the facade  ← dart compile js
  npm/                          # package.json, index.js, index.d.ts (hand-written)
```

**Recorded wrinkle:** `at_client_web` then does two jobs, and its name says "web" while
also serving Node. If the JS surface later grows to cover the collection API
([§5](#5-the-typescript-surface)), splitting is cheap — the facade is self-contained
under `lib/src/js/`.

---

## 5. The TypeScript surface

### 5.1 Keys are strings; metadata is a plain object

`AtKey` has **no JSON codec**. Every `toJson`/`fromJson` in
`packages/at_commons/lib/src/keystore/at_key.dart` belongs to `Metadata` (line 627/661)
or `AppMetadata` (852/862). `AtKey` offers only `toString()` — the wire form,
`public:phone.wavi@bob` — and a `fromString()` that is **lossy on metadata**. `AtValue`
has no codec at all.

So the boundary never materialises `AtKey` or `AtValue`. Keys cross as wire strings;
metadata crosses as a plain object, which `Metadata.toJson`/`fromJson` already supports.
This is also the atSign-native idiom, so it reads correctly to an app author.

### 5.2 The surface

```ts
const at = await AtClient.create({
  atSign: '@alice',
  namespace: 'wavi',
  keys: atKeysJson,            // bytes/JSON — never a file path
  rootDomain: 'root.atsign.org:64',
  storage?: KeyStore,          // TS-supplied backend; required on Node (§7)
});

// data
await at.put('phone.wavi@bob', '+15551234', { ttl: 60_000 });
await at.get('phone.wavi@bob');            // Promise<string | null>
await at.putBinary('avatar.wavi@bob', bytes);   // Uint8Array
await at.getBinary('avatar.wavi@bob');     // Promise<Uint8Array | null>
await at.delete('phone.wavi@bob');
await at.exists('phone.wavi@bob');         // Promise<boolean>
await at.getKeys({ regex: '\\.wavi@' });   // Promise<string[]>
await at.getMeta('phone.wavi@bob');        // Promise<Metadata | null>
await at.putMeta('phone.wavi@bob', meta);

// notification
await at.notify({ to: '@bob', namespace: 'wavi', body: 'hi' });
const off = at.onNotification(n => …);     // returns unsubscribe
await at.notificationStatus(id);

// sync
await at.waitUntilCaughtUp();
await at.isInSync();                       // Promise<boolean>

// lifecycle
await at.close();
```

Roughly **25 methods and 10 data types**. Every one maps to a live, non-deprecated
member of `at_client_spec.dart`, `notification_service.dart` or `sync_service.dart`.

`NotificationService.send()` is the mapping target for `notify` — it already takes only
primitives. `NotificationParams` is not bound: its 11 fields are private with no public
setters, constructible only via three static factories.

### 5.3 The collection API is phase two

`AtCollection<T>` is *already* JSON end-to-end — it takes a
`T Function(Map<String,dynamic>) fromJson` plus a `typeTag`, and persists with
`jsonEncode(item.toJson())`. So the value plane costs nothing to bridge.

Two things make it a separate, later piece of work:

- **The registry is keyed on Dart's reified `Type`** (`Map<Type, _FactoryEntry>`), and
  the auto-tag path uses `obj.runtimeType.toString()`. TypeScript erases generics, so a
  TS binding must **always** pass `typeTag` explicitly — the API half-anticipates this
  already by warning that deriving the tag from `T.toString()` is unsafe under
  minification.
- **`Query.where(bool Function(CItem<T>))` is a per-item closure.** A JS callback works
  (measured), but pays a boundary crossing per item. The serialisable
  `wherePath(Predicate)` is the TypeScript-appropriate path and should be the only one
  exposed.

~30 types and ~40 methods. Design it against `wherePath` only, after
[§5.2](#52-the-surface) ships.

---

## 6. Error mapping

**Mandatory, not optional.**

A Dart exception crossing a converted `Future` produces a rejection whose message is:

```
Dart exception thrown from converted Future. Use the properties 'error' to fetch
the boxed error and 'stack' to recover the stack trace.
```

The real exception is reachable only as a `JSBoxedDartObject` on `e.error` — opaque to
JavaScript, unboxable only by Dart in the same runtime. The Dart API docs carry a
maintainer TODO acknowledging this is *"pretty much useless to the user."*

Against at_commons' exception hierarchy (`packages/at_commons/lib/src/exception/`, ~50
classes), the facade must catch on the Dart side and rethrow a JS-shaped error:

```ts
class AtError extends Error {
  readonly code: string;      // stable, from AtExceptionCodes
  readonly kind: string;      // e.g. 'AtKeyException'
  readonly retriable: boolean;
}
```

Codes must be stable across releases — they are the only thing a TypeScript consumer can
branch on. Never surface the boxed handle.

---

## 7. TypeScript-supplied implementations, and Node

Because JavaScript objects can satisfy Dart interfaces
([§1.5](#15-javascript-can-implement-a-dart-interface)), the facade accepts
implementations from the consumer:

```ts
interface KeyStore {
  read(key: string): Promise<string | null>;
  write(key: string, value: string): Promise<void>;
  remove(key: string): Promise<void>;
  keys(): Promise<string[]>;
}
```

The browser default is supplied Dart-side by `at_client_web`. **Node has no `indexedDB`
and no `localStorage`**, so a Node consumer supplies its own — filesystem-backed, in a
dozen lines of TypeScript — and no Dart `at_client_node` package is needed.

What Node 24 *does* provide, and therefore needs no substitute: `WebSocket`,
`crypto.subtle`, `fetch`, `navigator`.

### The Node loader shim

Node defines neither `self` nor `MutationObserver`. dart2js schedules its microtasks off
those, so without them **every Promise silently never settles** — no error, no rejection,
no timeout. Just a hang.

```js
globalThis.self = globalThis;   // must run BEFORE the compiled bundle loads
```

This belongs in the npm package's loader and must never be the consumer's problem. It is
also precisely the silent-failure class this programme exists to remove, which is why
[`acceptance.md`](acceptance.md) T6 requires **timeout-bounded** assertions rather than a
bare `await`.

---

## 8. npm packaging

```
@atsign/at-client
  package.json        # "exports": { ".": { "types": "./index.d.ts", "default": "./index.js" } }
  index.js            # sets globalThis.self on Node, loads the bundle, re-exports the facade
  index.d.ts          # hand-written
  at_client.js        # dart compile js output
  at_client.js.map
```

Notes:

- **The exported object is installed on the global scope** by `main()`, and `index.js`
  re-exports from there. There is no official Dart mechanism for exporting a module
  surface — the Dart team states the "sharing" step is unsolved — so this convention is
  the supported path, and is what Sass does at scale.
- **Ship the source map.** dart2js output is minified; without `.js.map` a consumer
  stack trace is unreadable.
- **No bundler configuration is required**, which is the main practical dividend of
  [§2](#2-compile-target-dart2js). A dart2wasm build would need per-bundler `.wasm` asset
  handling, a CSP allowance, and an `application/wasm` MIME type from the host.

---

## 9. Deliberately excluded

| Excluded                                                                                               | Why                                                                                                                                                                              |
| ------------------------------------------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| File transfer — `uploadFile`, `downloadFile`, `reuploadFiles`, `shareFiles`, `stream`, `sendStreamAck` | All take `dart:io File`, all deprecated. Blocked on [`design.md`](design.md) §2.8 regardless.                                                                                    |
| The 12 `@Deprecated` members of `at_client_spec.dart`                                                  | Including `notify`, `notifyChange`, `notifyAll`, `startMonitor`. `NotificationService` supersedes them.                                                                          |
| `AtKey` / `AtValue` as objects                                                                         | No JSON codec; `fromString` is lossy. [§5.1](#51-keys-are-strings-metadata-is-a-plain-object).                                                                                   |
| `LocalSecondary` / `RemoteSecondary`                                                                   | Raw protocol escape hatches; implementation detail.                                                                                                                              |
| `CryptoProvider`                                                                                       | Requires implementing a Dart abstract class. A JS-supplied provider is possible in principle ([§1.5](#15-javascript-can-implement-a-dart-interface)) but is not in this surface. |
| `AtPersistenceBundle`, `AtChops`, `EncryptionService` getters                                          | Dart-only handles with no meaningful JS representation.                                                                                                                          |
| `ConnectivityListener`                                                                                 | Deprecated, and platform-probing.                                                                                                                                                |

---

## 10. Risks

- **`@JSExport` is officially framed for mocking.** Its only prose documentation is "How
  to mock JavaScript interop objects", and the `js_interop` owner describes it that way.
  It exports **instance members only** — no constructors, no statics, no prototype chain.
  Confirmed by probe: methods land as own properties and the prototype is empty. So
  `new`, `instanceof` and inheritance do not work JS-side. The facade must therefore be
  factory-constructed (`AtClient.create(...)`), which [§5.2](#52-the-surface) already is.
- **No official module-export mechanism exists.** Mitigated by the global-install
  convention ([§8](#8-npm-packaging)). Choosing dart2js also sidesteps
  `@pragma('wasm:export')`, which is dart2wasm-only *and* marked internal-use-only.
- **`.d.ts` is hand-written and has no drift detection.** Every existing tool converts
  `.d.ts` → Dart, not the reverse. Keeping it in sync is a maintenance obligation; T6
  should exercise the typings, not just the runtime.
- **`dart:html` is deprecated** (Dart 3.7; "will stop working in the future"). It
  compiles under dart2js today, so a *dependency* may rely on it silently — a risk to
  track, never a path for our own code.
- **Local SDK trails stable.** These measurements are on 3.12.0; current stable is 3.13.
  Re-measure on upgrade.

---

## 11. Open questions

**JS-1 — Which path does `cryptography` select under dart2js, and is it faster?**
Its Web Crypto path becomes reachable ([§3](#3-what-choosing-dart2js-changes-upstream)).
If it activates, Argon2id and AES may be fast enough to close the deferred performance
work outright. Measure before assuming either way.

**JS-2 — Does the facade expose `AtCollection`, and when?** [§5.3](#53-the-collection-api-is-phase-two)
argues for phase two, `wherePath`-only. AI-agent consumers may want it first, since it is
the higher-level API.

**JS-3 — Should the npm package ship a dart2wasm build too?** Zero source cost, twice the
artifacts and test matrix. `build_web_compilers` and Flutter both feature-detect and pick
at load time. Revisit if a consumer reports a startup or size problem — not before.

**JS-4 — Does `at_client_web` keep both jobs?** It would host the Dart platform
implementations *and* the JS facade, while serving Node as well as browsers
([§4](#4-where-the-facade-lives)). Acceptable now; revisit if the facade grows.

**JS-5 — Who owns the `.d.ts` and the npm release?** Publishing to npm is a new release
channel for this repo, with no CI, no versioning convention, and no owner today.
