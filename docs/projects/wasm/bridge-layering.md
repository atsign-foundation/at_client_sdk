# Proposed layering of `at_client_web` (D-38..D-41, D-45)

**Status: Proposed (D-38..D-41, D-45).** No proposed layer is built on trunk, and this does
not bind until the rows in [`docs/architecture/decisions.md`](../../architecture/decisions.md)
are accepted. The layer allocations this page describes for the closed state, regex compilation, namespace
folding, id lowercasing and error mapping are re-proposed by the implementing PRs, which carry their tests;
D-42..D-44 are reserved for them. Trunk's `at_client_web` has `portalSession`, `passkeyLogin` and
`lib/src/collections/js_collections_adapter.dart`, and no `lib/src/js/` bridge yet;
[`js-api.md`](js-api.md) section 4 says where the facade lives. The "Today" names and
columns below are those of the bridge implementation that follows these decisions (#2537),
not yet on trunk, except these names, which are on trunk too: `portalSession`,
`passkeyLogin`, `PortalSessionOfflineException`, `JsCollectionsError`, `JsCollectionsAdapter`,
`JsItem`, `JsItemAddress`, `JsListing`, `JsWhereClause`, `JsEvent`, `JsUnreadable`, the adapter's `_write`,
`_guard`, `_error` and `_errorId`, and the file `js_collections_adapter.dart`. The names below are the proposed ones; the rename table at the end maps each
to what it is called now.

JS values enter the bridge only at its top layer; below the bridge the session and adapter
layers take typed Dart. Existing platform helpers that need browser
APIs (the passkey, storage and setup helpers under `lib/src/keys/` and `lib/src/session/`) keep their own
`dart:js_interop` use; no decision here moves them behind the opener.

```mermaid
flowchart TD
  JS["JS caller (at_js)"] --> B["Bridge: lib/src/js/ (JS shapes, error codes)"]
  B --> S["Session: lib/src/session/ (domain rules)"]
  S --> C["Collections adapter: lib/src/collections/"]
  S --> O["SessionOpener: KeysSessionOpener, PasskeySessionOpener"]
  C --> AC["at_client: AtCollection"]
  O --> AC2["at_client: AtClient"]
  X["lib/src/exceptions.dart"] -.-> B
  X -.-> S
  X -.-> C
```

| Layer | Where | Holds | Does not hold |
|---|---|---|---|
| Bridge | `lib/src/js/` (`bridge.dart`, `error_codes.dart`) | The only file in the bridge that touches `dart:js_interop`. `BridgeEntry`, `BridgeSession`, `BridgeCollection`. Shape checks (plain object, own property, string, function, array, finite number, depth), the converters `_toDart`, `_toJs`, `_toRejection`. | Closed-state checks, regex compilation, namespace folding, id lowercasing, key parsing, any rule about what an atSign may do. |
| Session | `lib/src/session/` (`session.dart`, `at_client_session.dart`) | The `Session` interface and `AtClientSession`: the closed state, the namespace folded once in the constructor, the subscribe regex compiled once, incoming senders verified, the `__manage` grant, one decision per enrollment id at a time, one shared teardown that awaits the opener's stop. `SessionBoundCollection`, `ReceivedNotification`, `JsEnrollment`. | Any `dart:js_interop` type in the session interface or its domain rules (platform helpers under `lib/src/session/web_*.dart` keep their own), any error code. |
| Opening | `lib/src/session/` | `SessionOpener` (interface), `KeysSessionOpener`, `PasskeySessionOpener`, sealed `SessionOptions` (`KeysSessionOptions`, `PasskeySessionOptions`), `OpenedSession`. The opener validates its own options, including the root domain. | Anything the bridge needs to know about transports. The bridge no longer imports `portal_session`, `session_transport` or the transport options. |
| Collections adapter | `lib/src/collections/at_collection_adapter.dart` | `ItemCollection` (the eight operations) and `AtCollectionAdapter` over one `AtCollection`: the per-(id, owner) write queue, the id lowercased once, the type check on update, unreadable records listed instead of failing the call, a typed exception. | Codes and message text. |
| Exceptions | `lib/src/exceptions.dart` | Every exception the package declares, each to extend `AtException`: `PortalSessionOfflineException`, `UnsupportedKeyMaterialException`, `JsCollectionsError`, `SetupLockTimeoutException` and `IndexedDbException`, all on trunk today, move into this one file. | Code mapping, which stays in the bridge. |
| Contract manifest | release asset `bridge-manifest.json` | A `schemaVersion`, every exported method and every error code, generated from the Dart constants and identical for both compile targets. at_js downloads it with the bundle, checks its sha256 against `bridge.ref`, and fails when its TypeScript types or code list disagree. | Anything written by hand. |
| Build target | `tool/build.sh`, `at_client_web_bridge_release.yaml` | `--target dart2js\|dart2wasm`: `dart2js` by default; `dart2wasm` is strict, with no silent fallback; an unknown target exits 1. The release workflow takes the target as a dispatch input, read through `env:`, tags a wasm release distinctly (for example `at_client_web-bridge-wasm-<first 12 characters of the SHA>`) and attests every asset. | A target chosen by which entry name is passed. |

## Opening a session (D-40)

The shape, as a sketch; member names are not fixed until the code lands.

```dart
sealed class SessionOptions {}                       // KeysSessionOptions, PasskeySessionOptions
abstract interface class SessionOpener {
  Future<OpenedSession> open(SessionOptions options);
}
final class OpenedSession {                          // what every opener returns
  AtClient get client;
  Future<void> stop();                               // close() awaits this
}
```

`KeysSessionOpener` is today's `portalSession`; `PasskeySessionOpener` is today's
`passkeyLogin`. They are renamed as a pair rather than wrapped. A failure after the opener
has returned stops the opened session before it is rethrown, so a passkey's vault is never
left open. Validation runs first, in a fixed order, before any side effect, and rejects with
an argument error without echoing a value.

## Rename table (D-45)

Rules: each name says what it does and names its layer; siblings share a suffix; an
interface takes the plain noun and an implementation adds a qualifier; nothing pure-Dart
starts with `Js`. JS-facing names (`create`, method names, event shapes, error codes) do not
change. The table lists the names on trunk that change; names introduced in #2537 are not
proposed here.

| Layer | Today | Proposed | Why |
|---|---|---|---|
| Opening | portalSession | KeysSessionOpener | Opens with an .atKeys file |
| Opening | passkeyLogin | PasskeySessionOpener | Sibling of KeysSessionOpener |
| Opening | AtClient + stop (unnamed) | OpenedSession | What every opener returns |
| Opening | PortalSessionOfflineException | SessionOfflineException | Drop "portal" |
| Collection | JsCollectionsAdapter | AtCollectionAdapter | Adapts AtCollection to ItemCollection |
| Collection | JsItem, JsItemAddress, JsListing, JsWhereClause, JsEvent | Item, ItemAddress, ItemListing, WhereClause, CollectionEvent | Drop Js; match at_js names |
| Collection | JsUnreadable | UnreadableItem | Drop Js; match at_js names |
| Collection | _write, _guard, _error | _ownedWrite, _mapFailures, _toCollectionException | Say what each step does |
| Collection | js_collections_adapter.dart | at_collection_adapter.dart | Match the class |
| Exceptions | JsCollectionsError | CollectionException | Drop Js; it is pure Dart |
| Exceptions | spread over four files | lib/src/exceptions.dart | One file (D-41) |
