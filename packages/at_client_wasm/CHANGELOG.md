## 0.1.0

- Initial pre-release (unpublished): `portalSession` opens an ordinary `at_client` in the browser on in-memory storage and caller-supplied `AtKeys`, returning only once PKAM has succeeded.
- Direct transport by default; a dev proxy only when `proxyHost` and `proxyPort` are both set.
- Passkey custody (Gate C): `onboardNewAtSign`, `passkeyLogin` (`atSign` required) and `prfSupported`, with typed exceptions (`PrfUnavailableException`, `PasskeyLostException`, `PublicKeyMismatchException`, `MissingAtKeysDocumentException`). Onboarding keeps the activated keys until the sealed document is written: a write failure throws `OnboardingIncompleteException` with a handle that resumes or abandons. v1 limits: [`browser-onboarding.md`](../../docs/projects/wasm/browser-onboarding.md) §7.
- Setup-lock acquisition gives up after two minutes with `SetupLockTimeoutException`, and passkey create/get ceremonies carry a two-minute timeout.
