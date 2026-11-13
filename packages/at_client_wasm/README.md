# at_client_wasm

Opens an ordinary `at_client` in a browser from caller-supplied `AtKeys`.
This is a pre-release and unpublished package intended for WebAssembly/browser targets.

- `portalSession` builds the client on `InMemoryAtClientStorage` and an in-memory key store, authenticates with PKAM, and returns it only once it is online. Nothing is written to disk or IndexedDB. An open the atServer refuses throws `AtOpenRefusedException`, pending-only keys throw `AtEnrollmentPendingException`, and any other open that does not come online throws `PortalSessionOfflineException`.
- Transport is direct by default: the browser reaches each atSign's own atServer over `wss://host:port/ws`. A dev proxy is used only when `proxyHost` and `proxyPort` are both given to `DevSessionOptions`. There is no fallback from one to the other. See [docs/direct-mode.md](docs/direct-mode.md).
- Keys that carry ML-DSA-65 signing or namespace key material are refused for now (`UnsupportedKeyMaterialException`, before any connection). The passkey-onboarding work lifts this.
- Reads and writes go to the atServer (`RemoteLocalPref.remoteOnly`) unless the caller passes its own `prefs`. A `remoteOnly` client keeps nothing on the device to sync, so it runs a sync service that never contacts the atServer and always reports in sync; any other preference gets the default sync.
- The atSign goes through `toAtsign()`: `alice` and `@Alice` open the same session, and an atSign it rejects, such as one with whitespace, throws `InvalidAtSignException`.
- Opens for one atSign run one at a time. An open started while another is running waits for it, then fails with a `StateError` if that client is live, or builds afresh if it failed.

## Browser entry points

`package:at_client_wasm/at_client_wasm_web.dart` exports everything in `at_client_wasm.dart` plus the browser transports:

- `sessionTransport(DevSessionOptions)` returns the `SessionTransport` (`lookUps` + `finder`) that `portalSession` takes: direct, or the dev proxy when `proxyHost` and `proxyPort` are set.
- `proxyWebSocketLookUps(host:, port:, path: '/ws')` builds the lookup factory for the proxy, and `proxyPreamble(atSign)` is the first command each of its connections sends: `from:<atSign>`. A proxy that fronts many atServers reads it to learn which atServer the connection is for.

## Building the browser entry

`bash tool/build.sh` compiles `web/at_client_wasm_entry.dart` into `build/`: `at_client.js` (dart2js) and `at_client.wasm` plus `at_client.mjs` (dart2wasm), unminified so class names survive. If the dart2wasm compile fails the script warns and exits 0, leaving `at_client.js`; with `WASM_REQUIRED=1` that failure exits 1.

