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
**Revised 2026-08-18:** §5 rewritten end-to-end — the flat key/value plane is removed
(D-10) and `AtCollection<T>` (`packages/at_client/lib/src/collections/collections.dart`)
is the sole JS/TS data plane (D-9 amended, D-11 added). §6, §8, §9, §10 and §11 updated to
match; see `decisions.md` §2.6 for the measured findings this rewrite is based on and
`plans/wasm/api-designing.md` §2.3–§2.4 for the Dart-side (Layer B/C) shape.

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

**Revised 2026-08-18 — D-9 amended, D-10 and D-11 added.** The flat key/value plane
(§5.2 as originally written: `put`/`get`/`delete`/`exists`/`getKeys`/`getMeta`/`putMeta`)
is **removed**, not deprecated in place. `AtCollection<T>`
(`packages/at_client/lib/src/collections/collections.dart`, 5,306 lines, exported clean at
`at_client.dart:28`) is the **sole** JS/TS data plane. The older `at_collection/` tree
(`AtCollectionModel`, `AtJsonCollectionModel`, factories) is `@Deprecated` at
`at_client.dart:31-38` in favour of it and is never bound — see [§9](#9-deliberately-excluded).

### 5.1 Why no raw key plane is exposed at all

The original §5.1 argued `AtKey`/`AtValue` never materialise because `AtKey` has no JSON
codec and `fromString()` is lossy on metadata. That argument still holds, but it is no
longer the operative one: **there is no raw key plane on either side of the boundary to
materialise them into.** Collections are JSON end-to-end — `CItem<T>` persists as
`jsonEncode({'type': tag, 'obj': payload})` — so a JS consumer never constructs or parses
a wire-format key string at all. Every key, in the wire sense, is an implementation detail
inside `AtCollection`.

### 5.2 The two gears, and why the Dart side must be typed

The JS and Dart gears mesh at exactly one point: the wire `typeTag`, a plain `String`.
Everything else that would make an instantiation "typed" in the Dart sense — the generic
`T`, the `fromJson` closure, `PathField.extract` — is a Dart-only mechanism with no JS
counterpart.

**Read compatibility is unconditional.** `_rehydrate` (`collections.dart:3033-3062`) looks
up the factory by the tag stored *on the envelope*, not by the collection's Dart `T`. An
unregistered tag logs one warning and falls back to a raw cast — it does not throw. So a
JS collection reading data written by a typed Dart peer degrades gracefully to a plain
object, and `CItem.type` (`:4726`) surfaces the tag as a discriminator.

**Write compatibility is the open gap.** `_resolveType` (`:2960-2965`) stamps the write
tag from `obj.runtimeType` — a reified Dart `Type` with no JS equivalent. Every record a
JS binding writes stamps `type: 'n/a'` unless the facade does something about it. A JS
client and a Dart client therefore **cannot share a collection as equals** until one of:

| Route | Mechanism |
| --- | --- |
| **A — upstream `writeTypeTag`** (preferred) | An additive, non-breaking override on `AtCollection` that lets a caller supply the write-side tag directly, bypassing the `Type`-keyed lookup. |
| **B — carrier-class shim** (fallback) | The facade pre-declares N Dart wrapper classes, each holding a `Map` with `toJson()`, and binds a declared tag to each via `registerFactory`. Verified mechanically viable: `CItem.toJson()` (`:4803-4816`) emits `{'type', 'obj'}` and the caller `jsonEncode`s it (`:1088`), which invokes `toJson()` on a non-primitive payload. Bounded by a fixed ceiling of concurrent tags per isolate. |

State this asymmetry to every consumer, prominently: **the JS surface is read-compatible
with typed Dart peers, not yet write-compatible.**

### 5.3 The surface

Facade method names below are the ergonomic (Layer B) names, not upstream's — see the
mapping table in §5.4. `defineCollection`/`collection` auto-qualifies the namespace against
the client's configured namespace and defaults `expiration`; neither is required upstream
behaviour (`at_client_spec.dart:692-699`, `:735-742`), both are facade decisions.

```ts
const at = await AtClient.create({
  atSign: '@alice',
  namespace: 'wavi',
  keys: atKeysJson,            // bytes/JSON — never a file path
  rootDomain: 'root.atsign.org:64',
  storage?: KeyStore,          // TS-supplied backend; required on Node (§7)
});

// the sole data plane
const todos = await at.collection<Todo>('todos', {
  type: 'Todo',                // the wire typeTag — mandatory (TS erases T)
  expiration: 7 * 24 * 3600_000,  // ms; defaulted if omitted
  eventSource: 'data',         // 'data' | 'notifs' | 'both', default 'data'
});

const item = await todos.create({ title: 'ship wasm' }, { sharedWith: ['@bob'] });
item.id; item.owner; item.type; item.data; item.sharedWith;     // never `item.obj`

await todos.update(item.id, { title: 'ship wasm', done: true });
await todos.share(item.id, ['@bob', '@carol']);
await todos.remove(item.id, { cascade: true });

const overdue = await todos.where('done', '==', false)
  .orderByPath('due')            // facade invention — no upstream path-based ordering
  .limit(20)
  .get();

const off = todos.watch(e => { /* discriminated union on e.type; default branch
                                    required — CEvent is not sealed upstream */ });

// notification (not a collection concern)
await at.notify({ to: '@bob', namespace: 'wavi', body: 'hi' });
await at.notificationStatus(id);

// sync — collections read a LOCAL synced store; without this the surface is silently stale
await at.waitUntilCaughtUp();
await at.isInSync();

// lifecycle
await at.close();
```

**Four ergonomic fixes, all facade-side, benchmarked against Firestore/supabase-js/stripe-node
— none require an upstream change:**

| # | Leak if left as a literal transliteration | Fix shown above |
| --- | --- | --- |
| 1 | `item.obj.title` — the Dart envelope escaping into JS | renamed to `item.data` |
| 2 | `wherePath({path:['obj','done'], op:'eq', value:false})` — the AST spelled out longhand, re-leaking `obj` | `.where('done', '==', false)` — facade builds the AST |
| 3 | `defaultExpiration` required, with no hint what to pass | defaulted; override via `expiration` |
| 4 | fully-qualified reversed namespace (`'todos.myapp.wavi'`) when the client already knows the app namespace | auto-qualified; raw form still accepted as an override |

**Two caveats that no amount of facade polish removes, and must ship in the same
paragraph as the code above, not buried in §10:**

- **Queries run client-side over the local synced store.** Server-side filtering is
  architecturally impossible under end-to-end encryption — the server never sees
  plaintext to filter on — and upstream's own design assessment states it is not on the
  roadmap. A consumer arriving from a server-filtered SDK (Firestore, supabase) will
  expect pagination and remote filtering; on a large collection this is a memory and
  latency cliff, not a missing convenience method.
- **No `dispose()` exists upstream** (`collections.dart:439`/`:447`; the
  `availableEvents` scheduler runs for the collection's lifetime, `:2786-2788`). The
  facade relies on `AtClient.collection`'s `(namespace, eventSource)` cache
  (`at_client_impl.dart:256`) rather than constructing per JS object, which bounds but
  does not eliminate the leak — an SPA that changes routes still accumulates
  subscriptions per distinct collection it has ever opened.

### 5.4 Mapping table — Dart to JS/TS

| Dart | JS/TS | Note |
| --- | --- | --- |
| `AtCollection<T>` | `Collection<T>` handle from `at.collection()` | one instantiation per declared `(name, type)`; `T` is TS-side only |
| `CItem<T>` | `{ id, owner, type, data, sharedWith, createdAt, expiresAt, availableAt }` | `type` is the wire tag; `data` replaces `obj` (§5.3's fixes) |
| `CItem.ancestors` → `List<({Atsign owner, String id})>` | `{owner, id}[]` | Dart record — no natural JS shape, flattened |
| `Duration defaultExpiration` (positional, required upstream) | `expiration?: number` (ms), defaulted by the facade | positional-required upstream; optional in the facade |
| `EventSource` | `'data' \| 'notifs' \| 'both'` | default `'data'` in the facade (upstream defaults `'both'`, which double-fires) |
| `CEvent` + 7 subclasses (`CItemUpdated`, `CItemDeleted`, `CItemAvailable`, `CItemExpiringSoon`, `CSubItemUpdated`, `CSubItemDeleted`, `CReadReceipt`) | discriminated union on `type` | **not sealed upstream** — the encoder and every consumer switch need a default branch |
| `Atsign` (`extension type Atsign._(String)`, erased at runtime) | `string` | `toAtsign()` normalises (lowercase, prepend `@`, strip right-side dots) and validates — route through Dart, never replicate in JS |
| `Predicate` AST (`PathField`, `CmpPredicate`, `AndPredicate`, `OrPredicate`, `NotPredicate`) | `.where(path, op, value)` chain | not serializable upstream (private `CmpPredicate._`, closure `PathField.extract`) — the facade builds the AST from primitives, JS never sees it |
| `PredicateOp` (13 members; `like`/`inSet`/`between`/`contains`/`startsWith` throw `UnimplementedError`) | 8 working ops only | the 5 reserved ops must never appear as functional in the `.d.ts` — see [§9](#9-deliberately-excluded) |
| `CollectionOpException` / `OpResult` / `OpSuccess` / `OpFailure` | folded into the `AtError` throw model | [§6](#6-error-mapping) rules throw; a second result-union model must not leak onto the boundary |
| `subCollection` / `getDescendant` | in scope, same declared-tag mechanism as the root | verify the `fromJson`/`typeTag` XOR check behaves identically to `AtClient.collection`'s (measured only for the root) |
| `watchWithTree` / `SubSpec` | **excluded** | `SubSpec` has no exported opener (`collections_test_hooks.dart:168`, `@visibleForTesting`, not in the barrel) — blocked on an upstream export, not a design choice |

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

**Collections introduce a second result shape upstream, and it folds into this one.**
`AtCollection`'s batch write paths (`delete(cascade: true)`, sub-collection sweeps) can
partially fail, and upstream represents that as `CollectionOpException` carrying a
`List<OpResult>` of `OpSuccess`/`OpFailure` values (`collections.dart:5010-5052`) rather
than throwing a single exception. **This must not become a second error-handling model on
the boundary.** The facade catches `CollectionOpException`, and rethrows a single
`AtError` whose `code` identifies it as a partial-failure case and whose `cause` (or an
equivalent structured field) carries the mapped `OpFailure.reason` entries. A JS consumer
sees one `AtError` shape regardless of whether the underlying failure was a single
exception or a batch of `OpFailure`s — never a tuple, never a second thrown type.

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
  package.json        # GENERATED by build tooling, not hand-committed — see below
  index.js            # sets globalThis.self on Node, loads the bundle, wraps the raw
                       # facade in a real ES class, re-exports it
  index.d.ts          # hand-written; documentation value, not generated (see below)
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
- **`package.json` should be generated, not hand-committed — corrected against verified
  dart-sass practice (2026-08-17).** dart-sass's root `package.json` holds only
  `devDependencies`; the published manifest is produced by build tooling
  (`pkg/sass-parser/package.json` uses `"exports": {"types": "./dist/types/index.d.ts",
  "default": "./dist/lib/index.js"}` — the same shape already shown above). Generating it
  removes a class of drift between the published `exports` map and the actual build
  output.
- **`index.js` restores what `@JSExport` cannot give you.** [§10](#10-risks) records that
  `@JSExport` exports **instance members only** — no constructor, no statics, no
  prototype chain, so `new`, `instanceof` and inheritance do not work on the raw compiled
  facade object. Rather than accept that in the public API, `index.js` wraps the raw
  export in a real ES class with a private constructor and a static async factory — the
  same internal-core / hand-authored-public-API split `automerge-wasm`/`automerge-js`
  uses:

  ```ts
  // index.d.ts
  export declare class AtClient {
    private constructor();                 // `new AtClient()` is a TS compile error
    static create(opts: AtClientOptions): Promise<AtClient>;
    collection<T>(name: string, opts: CollectionOptions): Promise<Collection<T>>;
    close(): Promise<void>;
  }
  ```

  ```js
  // index.js
  class AtClient {
    static async create(opts) { return new AtClient(await rawFacade.create(opts)); }
    collection(name, opts) { return this.#raw.collection(name, opts); }
    #raw;
  }
  ```

  This is where a `@JSExport`-produced object becomes a real, `instanceof`-checkable,
  autocomplete-friendly class — the compiled facade cannot do this on its own, and no
  amount of Layer B design (`plans/wasm/api-designing.md`) fixes it, because the
  limitation is in `@JSExport` itself.
- **The `.d.ts` stays hand-written.** Sass keeps its `.d.ts` in a *separate repo*
  (`sass/sass` → `js-api-doc/index.d.ts`), framed explicitly as user-facing documentation
  rather than generated types. `plans/wasm/api-designing.md` §2.6 (re-costed 2026-08-18
  for Layer B's generics) recommends **drift detection** — a CI diff of generated-vs-committed
  — over full generation, for the same reason: a hand-authored `.d.ts` carries
  documentation value generated output loses. See [§11](#11-open-questions) JS-5.

---

## 9. Deliberately excluded

| Excluded                                                                                               | Why                                                                                                                                                                              |
| ------------------------------------------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **The flat key/value plane** — `put`, `get`, `putBinary`, `getBinary`, `delete`, `exists`, `getKeys`, `getMeta`, `putMeta` | **Removed 2026-08-18 (D-10), not merely unbound.** `AtCollection<T>` is the sole JS data plane; a JS consumer cannot address a raw protocol key. |
| File transfer — `uploadFile`, `downloadFile`, `reuploadFiles`, `shareFiles`, `stream`, `sendStreamAck` | All take `dart:io File`, all deprecated. Blocked on [`design.md`](design.md) §2.8 regardless.                                                                                    |
| The 12 `@Deprecated` members of `at_client_spec.dart`                                                  | Including `notify`, `notifyChange`, `notifyAll`, `startMonitor`. `NotificationService` supersedes them.                                                                          |
| `AtKey` / `AtValue` as objects                                                                         | No JSON codec; `fromString` is lossy — and moot besides, since no raw key plane is exposed. [§5.1](#51-why-no-raw-key-plane-is-exposed-at-all).                                  |
| The entire deprecated `at_collection/` tree — `AtCollectionModel`, `AtCollectionModelFactory`, `KeyMaker`, `ObjectLifeCycleOptions`, `AtJsonCollectionModel` | `@Deprecated("Use AtClient.collection for collection-style operations")` at `at_client.dart:31-38`. Its registry keys on a lowercased class-name string (`T.toString().toLowerCase()`) — exactly the minifier-unsafe pattern the current API's mandatory `typeTag` exists to fix. |
| `watchWithTree` / `SubSpec` | `SubSpec` has no exported opener — its only constructor path, `_openOnForTest`, is `@visibleForTesting` in `collections_test_hooks.dart` and not exported from the barrel. Blocked on an upstream export. |
| `Query.fetch()` | `@Deprecated('use get() instead')` at `collections.dart:3566`. Bind `get()`. |
| `PredicateOp.like` / `.inSet` / `.between` / `.contains` / `.startsWith` | Reserved but unimplemented — `evaluate()` throws `UnimplementedError` (`collections.dart:4305-4307`). Only the 8 working ops (`eq`, `neq`, `lt`, `lte`, `gt`, `gte`, `isNull`, `isNotNull`) appear in the `.where()` type. |
| `LocalSecondary` / `RemoteSecondary`                                                                   | Raw protocol escape hatches; implementation detail.                                                                                                                              |
| `CryptoProvider`                                                                                       | Requires implementing a Dart abstract class. A JS-supplied provider is possible in principle ([§1.5](#15-javascript-can-implement-a-dart-interface)) but is not in this surface. |
| `AtPersistenceBundle`, `AtChops`, `EncryptionService` getters                                          | Dart-only handles with no meaningful JS representation.                                                                                                                          |
| `ConnectivityListener`                                                                                 | Deprecated, and platform-probing.                                                                                                                                                |
| `AtKey` leaking via `OpResult.atKey`                                                                    | The one place a raw `AtKey` survives inside upstream's collection result type. Folded away by [§6](#6-error-mapping)'s `AtError` mapping — never surfaced to JS. |

---

## 10. Risks

- **`@JSExport` is officially framed for mocking.** Its only prose documentation is "How
  to mock JavaScript interop objects", and the `js_interop` owner describes it that way.
  It exports **instance members only** — no constructors, no statics, no prototype chain.
  Confirmed by probe: methods land as own properties and the prototype is empty. So
  `new`, `instanceof` and inheritance do not work JS-side. The facade must therefore be
  factory-constructed (`AtClient.create(...)`), which [§5.3](#53-the-surface) already is.
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
- **The collections surface has zero end-to-end coverage against a real atServer.**
  `AtCollection`'s class doc (`collections.dart:58-62`) declares "Status: stable" and
  names real compatibility mechanisms (`interface class`, `final` event subclasses, enum
  slack) — this is not a dispute of that contract. But all 209 of its tests are mocktail
  unit tests against `MockAtClient`; nothing in `tests/at_functional_test/` or
  `tests/at_end2end_test/` references it. The API also took a breaking change 2 days
  after introduction (`fb4c96587`, mandatory `typeTag`), reworked `EventSource`
  semantics since, and ships 7 correctness fixes in the current 3.14.1. **Ruling: the
  JS-side collections surface ships marked unstable/0.x in the npm package** until this
  project's own T6/T4 gates exercise it against a live atServer — the marker reflects a
  gap in *our* boundary validation, not upstream's contract.
- **No `dispose()` on `AtCollection`, at all.** Every reference SDK in Axis C
  (§1 of `plans/wasm/api-designing.md`) has an explicit cleanup call
  (`removeChannel`, `stopClient`). Upstream's own comments (`collections.dart:439`/`:447`)
  acknowledge the gap ("Held so a future `dispose()` can cancel cleanly"), and
  `availableEvents`' scheduler runs for the collection's lifetime regardless
  (`:2786-2788`). The facade's `(namespace, eventSource)` cache bounds this to one leak
  per distinct collection a page has opened, not per object constructed — but does not
  eliminate it.
- **`CEvent` is deliberately not `sealed`** (`collections.dart:5077`) — new event
  subtypes can ship in a minor version. The JS discriminated union's encoder and every
  documented consumer pattern must include a default/unknown branch, or a future
  upstream minor silently breaks JS consumers that pattern-matched exhaustively.
- **Write-compatibility with typed Dart peers is unresolved** (§5.2). Until route A
  (upstream `writeTypeTag`) or route B (the carrier-class shim) ships, every record a JS
  binding writes stamps `type: 'n/a'` and cannot be rehydrated as a typed object by a
  Dart peer app. This is a real interop gap for a mixed JS+Dart fleet, not a documentation
  nicety — see [§11](#11-open-questions) JS-7.

---

## 11. Open questions

**JS-1 — Which path does `cryptography` select under dart2js, and is it faster?**
Its Web Crypto path becomes reachable ([§3](#3-what-choosing-dart2js-changes-upstream)).
If it activates, Argon2id and AES may be fast enough to close the deferred performance
work outright. Measure before assuming either way.

**JS-2 — Does the facade expose `AtCollection`, and when? RESOLVED 2026-08-18.** Not
merely exposed — it is now the **sole** JS data plane (D-10); the flat key/value plane is
removed. See [§5](#5-the-typescript-surface). Superseded the original "phase two,
`wherePath`-only" framing: the facade builds `Predicate` from a `.where(path, op, value)`
chain rather than binding `wherePath` directly, so JS never constructs the AST.

**JS-3 — Should the npm package ship a dart2wasm build too?** Zero source cost, twice the
artifacts and test matrix. `build_web_compilers` and Flutter both feature-detect and pick
at load time. Revisit if a consumer reports a startup or size problem — not before.

**JS-4 — Does `at_client_web` keep both jobs?** It would host the Dart platform
implementations *and* the JS facade, while serving Node as well as browsers
([§4](#4-where-the-facade-lives)). Acceptable now; revisit if the facade grows.

**JS-5 — Who owns the `.d.ts` and the npm release?** Publishing to npm is a new release
channel for this repo, with no CI, no versioning convention, and no owner today.

**JS-6 — Throw vs. return-tuple for the error surface?** [§6](#6-error-mapping) rules
`AtError extends Error` — every failure rejects the Promise, carrying a stable `.code`.
`supabase-js` takes the opposite lane: most calls resolve to `{ data, error }` and never
reject, on the theory that a forgotten `try`/`catch` degrades to an ignorable `error`
field rather than an unhandled rejection killing the process — the same failure class
[§1.2](#12-the-failure-mode-is-a-process-kill-not-a-type-error) documents. The throw
model stands as ruled — it is the more idiomatic shape for a Promise-first API and
matches the `stripe-node` precedent — but is not proven against real consumer feedback.
Revisit only if a consumer reports missed `.catch` in practice; do not pre-emptively
switch.

**JS-7 — Route A (`writeTypeTag`) or route B (carrier-class shim) for write-compatibility?**
[§5.2](#52-the-two-gears-and-why-the-dart-side-must-be-typed) identifies that every record
a JS binding writes stamps `type: 'n/a'` because `_resolveType` keys on a reified Dart
`Type` the JS side cannot supply. Route A needs an upstream, additive change and is this
project's preferred outcome; route B is bounded (a fixed ceiling of concurrent tags) and
achievable unilaterally in the facade. **Resolve on upstream's answer to the additive
change; document the gap and ship read-compatibility in the meantime.**

**JS-8 — `AtClientManager`'s singleton blocks multi-instance JS clients.**
`packages/at_client/lib/src/manager/at_client_manager.dart:48` holds a
`static final AtClientManager _singleton` driven by `setCurrentAtSign(...)`. A JS
consumer calling `AtClient.create({atSign: '@alice'})` then `AtClient.create({atSign:
'@bob'})` expects two independent clients — every reference SDK in Axis C
(`plans/wasm/api-designing.md` §1) is multi-instance by construction — but today the
second call mutates global state under the first. **Interim: ship documented as one
atSign per page/process, plus a facade-level `AtFailure.alreadyInitialised` thrown on a
second *distinct* atSign** (converts silent corruption into a clear error, ~10 lines in
Layer B). Making `AtClientManager` itself instantiable is a breaking major and separate
work — track it, do not fold it into this project's scope.
