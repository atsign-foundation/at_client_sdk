## Unreleased

- Release workflow `at_client_web_bridge_release.yaml`: a release is started by hand (`workflow_dispatch` from trunk). It builds `at_client_web.js` from `dart-workspace.lock` and attaches it with a sha256 file and a build provenance attestation to a prerelease tagged `at_client_web-bridge-<sha12>`.
- Browser bridge (`web/at_client_web_entry.dart`, built by `tool/build.sh` as `build/at_client_web.js`): `create` opens a keys-file session and returns `@JSExport` session and collection objects. Rejections carry `{code, message}`, with `id`, `owner`, `kind` and `failures` for collection failures; item data crosses as objects with no prototype.
- Session: `status()` and `onStatus(cb)` with the states `connecting`, `connected`, `waiting:network`, `waiting:server` and `waiting:auth`; collections over `JsCollectionsAdapter`; `subscribe` takes an `onError` and logs a warning for each dropped notification; pairing calls require the `__manage` grant at rw.
- Collection `create` and `update` reject `data` that is an array, nests more than 64 levels or contains a cycle, with code `internal` and a message naming `data`; arrays inside `data` stay valid.
- `JsCollection`: an interface of the eight collection operations. `JsCollectionsAdapter` stays `final` and implements it; the bridge depends on the interface.
- Notifications sent while the page is closed or reloading are never delivered.

## 0.1.0

- Initial pre-release (unpublished): `portalSession` opens an ordinary `at_client` in the browser on in-memory storage and caller-supplied `AtKeys`, returning only once PKAM has succeeded.
- Direct transport by default, chosen with `SessionTransportOptions`; a dev proxy only when `proxyHost` and `proxyPort` are both set, or a `proxy:<host>` root. A host is a bare name or a bracketed IPv6 literal such as `[::1]`; anything else throws an `ArgumentError` naming the field.
- `portalSession` throws an `ArgumentError` for a `prefs` whose root is not the transport's, including a default `AtClientPreference()` passed with a proxy transport.
