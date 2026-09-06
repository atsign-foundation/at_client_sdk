# `at_lookup` 4.0.0-rc1

Second package in the v4 publish chain. Depends on `at_utils` 4.0.0 — this branch
stacks on `st/at_utils-v4`'s tip before any code commit lands (`resolution: workspace`
makes this non-optional, not just tidy). Scope here is cut to **T1–T5**; T6–T8 stay
open (see Exit below).

## Context

`at_lookup` is step 4 of the publish ladder
([`implementation-plan.md`](../projects/wasm/implementation-plan.md) §10), Phase T (transport) —
"the largest item, and the one breaking change with an unknown external blast radius."

**The seam already exists.** `packages/at_lookup/lib/at_lookup_io.dart` re-exports
`at_lookup.dart` in full and adds `secureSocketTransport()`; its own doc comment states
the actual blocker: *"`AtConnection` still exposes `Socket getSocket()` ... What this
split buys is that the shape is already right when that change lands."*
`AtLookupTransport` (`src/at_lookup.dart:407-444`) already bundles the three connection
factories `AtLookupImpl` has always accepted, and that class's own doc says it plainly:
*"These factories are **already injectable**; what blocks a web transport is their
**return type** (`SecureSocket`), not their injectability."* So this release is **T3 +
T4 — flip the return types and delete `getSocket()`** — not "build a split."

## Scope

**In** (T1–T5 — T6–T8 held open, see Exit):

- **T1 — Audit `implements AtConnection` / `getSocket()` callers first.** In-repo:
  `remote_secondary.dart`, `monitor.dart`. External implementors are an open question
  (OQ-8 in `decisions.md`) — do this enumeration before writing anything, since the
  answer bounds how disruptive T3 actually is.
- **T2 — `AtTransport` is already defined as `AtLookupTransport`** (see Context). No new
  interface to write; this task is "confirm the existing bundle is the interface," not
  "design one."
- **T3 — Remove `Socket getSocket()` from the abstract `AtConnection` interface
  only.** Declared at `connection/at_connection.dart:10` (with `import 'dart:io'` at
  `:1`, the only import in that file) — delete the interface member and that file's
  `dart:io` import. `base_connection.dart` keeps `late final Socket _socket` and the
  method body (`:50-51`), just drops `@override`: it's a concrete, native-only method
  on `BaseConnection` now, not part of the public contract a non-native `AtConnection`
  implementation would have to satisfy. `outbound_connection.dart` and
  `outbound_connection_impl.dart` are untouched — `OutboundConnection extends
  BaseConnection` inherits the concrete method unchanged.
  **Why not delete it outright:** `monitor.dart:58` in `at_client` holds its connection
  as `OutboundConnection?` (the concrete type, not `AtConnection`) and calls
  `.getSocket()` at `:233` — verified at `124982684`. That call site is explicitly
  out of scope this release (T6, native raw-socket routing, stays open — see Exit), so
  it must keep compiling. `remote_secondary.dart:149` is the only other in-repo
  caller, and it's inside `addStreamData`, which `at_client.md`'s own scope deletes in
  this same release — that removes the one call site that *was* typed through the
  abstract interface. Net effect: the public `AtConnection` surface loses
  `getSocket()` (the actual WASM-facing break), while the native-only concrete class
  keeps it, and `at_client/test/monitor_test.dart`'s stub on `OutboundConnection`
  passes unchanged — confirmed against `124982684`'s actual class hierarchy, not
  assumed.
- **T4 — Retype the three factories at `at_lookup_impl.dart:1312-1338`** off
  `SecureSocket`: `AtLookupSecureSocketFactory.createSocket` (`:1315`, returns
  `Future<SecureSocket>`), `AtLookupSecureSocketListenerFactory.createListener`
  (`:1327`), `AtLookupOutboundConnectionFactory.createOutboundConnection` (`:1335`,
  takes `SecureSocket`). They're already injectable and plumbed through
  `AtLookupTransport`; only the type signatures change.
- **T5 — `at_lookup_io.dart` absorbs `src/util/secure_socket_util.dart`** whole
  (certs, `SecurityContext`, TLS keylog) as native-only.

**Also in scope — the pre-labelled credential-ladder cleanup**, all annotated for
removal at this major and gated by the same file this release already touches
(`src/at_lookup.dart`):

- `atChops` set/get, `signingAlgoType` set/get, `hashingAlgoType` set/get,
  `enrollmentId` set/get — `src/at_lookup.dart:150-209`, each
  `@Deprecated('...Removed with the credential ladder in the next major release.')`.
- The `AtLookupImpl` constructor itself — `@Deprecated` at `at_lookup_impl.dart:156`,
  `'Use AtLookUp.withSecureSocket... Removed in the next major release.'` — plus its
  backing `_atChops` field, marked `// TODO(4.0): remove with the credential ladder.`
  at `:138`.
- `MonitorClient` as a whole class (`monitor_client.dart:22`,
  `@Deprecated('...Removed in the next major release.')`) — superseded by
  `AtLookUp.withSecureSocket` + `AtLookupMuxable.notifications`.
- `findSecondary` (`at_lookup_impl.dart:182`, `@Deprecated('use
  CacheableSecondaryAddressFinder')`) and `authenticate_cram`
  (`:759`, `@Deprecated('use AtLookup().cramAuthenticate()')`) — narrower deprecation
  wording than the credential ladder's, but both are dead weight this major can drop.
- `executeVerb`'s inert `sync` parameter — `src/at_lookup.dart:119`,
  `@Deprecated('Inert: nothing reads it. The verb always executes ...')`.
- A doc-comment-only deprecation that `dart analyze` never flags: `at_lookup_impl.dart:606`
  carries `// @Deprecated('Use method pkamAuthenticate') Commenting deprecation since it
  causes issue in dart analyze in the caller` as a *comment*, not an annotation, on
  `authenticate()`. Fix the comment or add a real (ignored-at-call-site) annotation so
  callers actually see it.

**Out of scope, explicitly** (T6–T8 — see Exit for why):

- T6 — routing `monitor_client.dart`'s and `at_client`'s `stream_notification_handler.dart`'s
  direct `SecureSocket.connect` calls through the transport.
- T7 — a web `SecondaryAddressFinder`; `cache/cacheable_secondary_address_finder.dart`
  imports `dart:io` directly (`:3`) and its `SecondaryUrlFinder` helper, while it already
  creates sockets through the injectable `AtLookupSecureSocketFactory` (so T4's retype
  reaches it automatically), still carries the top-level `dart:io` import and a
  `proxy:<host>` convention (`:165`) as the only existing escape hatch. The production
  answer is OQ-7.
- T8 — publish. Blocked on T6/T7's residual reachability being resolved or gated.

## Dependency floors

`at_utils: ^4.0.0` (this ladder step). `at_commons: ^5.16.0 → ^5.17.0`.
`at_chops: ^3.6.0 → ^3.6.1`.

## Open items

1. **Resolved — `websocket_uptake` does not bind T2/T4's shape.** Checked
   `at_libraries.git@websocket_uptake` (`e22cffbed`, last commit 2025-01-15) and
   `origin/websocket_test` (same date) directly: both are ~8-month-stale, single-author
   spikes, and neither reaches the goal this ladder exists for — `AtWebSocketConnection`
   there still wraps `dart:io.WebSocket`, so it doesn't solve browser/WASM compat either.
   Its `AtConnection<T>` + `T get underlying` redesign is a different (broader,
   unfinished — `base_connection.dart` is left dead in that tree) shape than this
   release's minimal return-type flip. Decision: proceed independently per T2/T4 as
   specified above; do not retrofit the generic `underlying` shape. If that spike is
   ever revived, reconciling it against this release's `AtLookupTransport` is that
   effort's problem to solve, not a constraint on this one.
2. **Where does `AtTransport` (as `AtLookupTransport`) live long-term** — `at_lookup` or
   a future `at_transport` package? Deferred by the ladder until the interface is
   written; this release keeps it in `at_lookup` by default.
3. **Resolved — this checkout (`packages/at_lookup` in `at_client_sdk`) is canonical
   for this release.** `origin/websocket_test` points `at_client`'s dependency at
   `at_libraries.git@websocket_uptake` via a git override, but that branch is dead (see
   item 1) — there is no active alternative checkout to defer to. T1–T5 land here.

## Exit — no `wasm_gates.yaml` stanza this window

- `grep -n "dart:io" packages/at_lookup/lib/src/connection/at_connection.dart` →
  nothing.
- `packages/at_lookup/test/` green, including `connection_management_test.dart`
  retyped for the new factory signatures.
- `tests/at_functional_test` green.
- T5 moves `secure_socket_util.dart` behind `at_lookup_io.dart`, but **T6–T8 are not in
  scope**: `monitor_client.dart`'s raw `SecureSocket.connect` and
  `cacheable_secondary_address_finder.dart`'s direct `dart:io` import still reach native
  code from the default barrel after this release. That's a known, named follow-on, not
  a surprise discovered later.

## Changelog

```
## 4.0.0-rc1
- BREAKING: `AtConnection.getSocket()` removed. Use the connection's `AtTransport`
  (native transports still resolve to a `Socket` under `at_lookup_io.dart`, but the
  type is no longer exposed on the public interface).
- BREAKING: `AtLookupSecureSocketFactory.createSocket`,
  `AtLookupOutboundConnectionFactory.createOutboundConnection`, and the muxable
  factories retyped off `SecureSocket` onto `AtTransport`.
- Removed: `MonitorClient`, `AtLookupImpl`'s public constructor, the `atChops` /
  `signingAlgoType` / `hashingAlgoType` / `enrollmentId` accessors, `findSecondary`,
  `authenticate_cram`, and `executeVerb`'s `sync` parameter — all deprecated since
  earlier releases.
```
