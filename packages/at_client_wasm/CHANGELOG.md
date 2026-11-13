## 0.1.0

- Initial pre-release (unpublished): `portalSession` opens an ordinary `at_client` in the browser on in-memory storage and caller-supplied `AtKeys`, returning only once PKAM has succeeded.
- Direct transport by default; a dev proxy only when `proxyHost` and `proxyPort` are both set.
- Passkey custody (Gate C): `onboardNewAtSign`, `passkeyLogin` (`atSign` required) and `prfSupported`, with typed exceptions (`PrfUnavailableException`, `PasskeyLostException`, `PublicKeyMismatchException`, `MissingAtKeysDocumentException`). v1 limits: [`browser-onboarding.md`](../../docs/projects/wasm/browser-onboarding.md) §7.
