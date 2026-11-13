# at_client_wasm

Opens an ordinary `at_client` in a browser from caller-supplied `AtKeys`.
This is a pre-release and unpublished package intended for WebAssembly/browser targets.

- `portalSession` builds the client on `InMemoryAtClientStorage` and an in-memory key store, authenticates with PKAM, and returns it only once it is online. Nothing is written to disk or IndexedDB. A PKAM the atServer refuses, or any other open that does not come online, throws `PortalSessionOfflineException`.
- Transport is direct by default: the browser reaches each atSign's own atServer over `wss://host:port/ws`. A dev proxy is used only when `proxyHost` and `proxyPort` are both given to `DevSessionOptions`. There is no fallback from one to the other. See [docs/direct-mode.md](docs/direct-mode.md).
- Keys that carry ML-DSA-65 signing or namespace key material are refused for now (`UnsupportedKeyMaterialException`, before any connection). The passkey-onboarding work lifts this.
- The atSign is normalized (`alice`, `@Alice` and ` @alice ` open the same session).
