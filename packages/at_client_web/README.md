# at_client_web

Opens an ordinary `at_client` in a browser from caller-supplied `AtKeys`.
This is a pre-release and unpublished package intended for WebAssembly/browser targets.

- `portalSession` builds the client on `InMemoryAtClientStorage` and an in-memory key store, authenticates with PKAM, and returns it only once it is online. Nothing is written to disk or IndexedDB. An open the atServer refuses throws `AtOpenRefusedException`, pending-only keys throw `AtEnrollmentPendingException`, and any other open that does not come online throws `PortalSessionOfflineException`.
- Transport is direct by default: the browser reaches each Atsign's own atServer over `wss://host:port/ws`. A dev proxy is used only when `SessionTransportOptions` is given both `proxyHost` and `proxyPort`, or a `proxy:<host>` root. There is no fallback from one to the other. See [docs/direct-mode.md](docs/direct-mode.md).
- Keys that carry ML-DSA-65 signing or namespace key material are refused for now (`UnsupportedKeyMaterialException`, before any connection). The passkey-onboarding work lifts this.
- Reads and writes go to the atServer (`RemoteLocalPref.remoteOnly`) unless the caller passes its own `prefs`. Sync still runs, and starts at every open: it pulls the atServer's records into the in-memory store without the app asking. Under `remoteOnly` a put or delete goes to the atServer unless its request options set `useRemoteAtServer = false` explicitly. Only that keeps a write local (queued for sync); options that leave it unset do not.
- The Atsign goes through `toAtsign()`: `alice` and `@Alice` open the same session, and an Atsign it rejects, such as one with whitespace, throws `InvalidAtSignException`.
- Opens for one Atsign as one enrollment run one at a time. An open started while another for the same enrollment is running waits for it, then fails with a `StateError` if that client is live, or builds afresh if it failed. Opens for different enrollments of the Atsign do not wait on each other.

## Browser entry points

`package:at_client_web/at_client_web_web.dart` is the one import a browser app needs. It exports everything in `at_client_web.dart`; at_client's core API and in-memory storage; `onboardNewAtSign`, `passkeyLogin`, `prfSupported` and `clearPrfMiss` with the `PasskeySession` they return and the exceptions they throw or carry as a cause; and the browser transports:

- `sessionTransport(SessionTransportOptions)` returns the `SessionTransport` (`lookUps`, `finder` and `root`) that `portalSession` takes: direct, or the dev proxy when `proxyHost` and `proxyPort` are set or the root is `proxy:<host>`. A host, the proxy's or the root's, is a bare host of ASCII letters, digits, `.`, `-` and `_` only, or a bracketed IPv6 literal such as `[::1]`; `SessionTransportOptions` throws an `ArgumentError` naming the field for an empty host, one holding any other character outside such a literal, a port outside 1-65535, a `proxyHost` or `proxyPort` without the other, and a `root` given with a proxy. `portalSession` builds its preference on the transport's `root`, and refuses a `prefs` that names another root.
- Through the dev proxy, each connection goes to `wss://host:port/ws`, and at_lookup sends `from:<atSign>` first on it because the session's root is `proxy:<host>`. A proxy that fronts many atServers reads it to learn which atServer the connection is for.
- If you pass your own prefs, set their rootDomain and rootPort to match the transport's root; a default AtClientPreference() names the production root, so passing it with a proxy transport throws an ArgumentError before connecting.

## Building the browser entry

`bash tool/build.sh` compiles `web/at_client_web_entry.dart` into `build/`: `at_client.js` (dart2js) and `at_client.wasm` plus `at_client.mjs` (dart2wasm), unminified so class names survive. If the dart2wasm compile fails the script warns and exits 0, leaving `at_client.js`; with `WASM_REQUIRED=1` that failure exits 1.

The same script also compiles the browser bridge, `web/at_client_bridge_entry.dart`, to `build/at_client_web.js` (and `at_client_web.wasm` plus `at_client_web.mjs`); `bash tool/build.sh at_client_bridge_entry` builds only the dart2js bridge.

Arguments:

- **No arguments** keeps the behaviour above: both entries, dart2js plus a best-effort dart2wasm.
- **`--target dart2js`** or **`--target dart2wasm`** (also written `--target=dart2js` or `--target=dart2wasm`) builds that compile target only, for both entries unless `at_client_bridge_entry` is named as well. Each build removes the entry's stale `.js`, `.wasm` and `.mjs` first, so `build/` never holds both targets of one entry.
- **`--target dart2wasm`** forces `WASM_REQUIRED=1`: a wasm compile failure exits 1 instead of warning and leaving the `.js`.
- **`at_client_bridge_entry`** with no `--target` is the dart2js bridge only, as before.
- **Anything else exits 1**, naming the allowed values: `--target both`, `--target=` (empty), an unknown target, and an unknown entry are all refused.

The release workflow builds one target per release (`dart2js` by default) and publishes that target's files only: `at_client_web.js` for dart2js, and `at_client_web.wasm` plus `at_client_web.mjs` for dart2wasm. See [`docs/projects/wasm/acceptance.md`](../../docs/projects/wasm/acceptance.md) §9b and D-36 in `docs/architecture/decisions.md` (proposed).
