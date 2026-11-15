## 0.1.0

- Initial pre-release (unpublished): `portalSession` opens an ordinary `at_client` in the browser on in-memory storage and caller-supplied `AtKeys`, returning only once PKAM has succeeded.
- Direct transport by default; a dev proxy only when `proxyHost` and `proxyPort` are both set.
- Passkey custody (Gate C): `onboardNewAtSign`, `passkeyLogin` (`atSign` required) and `prfSupported`, with typed exceptions (`PrfUnavailableException`, `PasskeyLostException`, `PublicKeyMismatchException`, `MissingAtKeysDocumentException`). Onboarding keeps the activated keys until the sealed document is written: a write failure throws `OnboardingIncompleteException` with a handle that resumes or abandons. v1 limits: [`browser-onboarding.md`](../../docs/projects/wasm/browser-onboarding.md) §7.
- Setup-lock acquisition gives up after two minutes with `SetupLockTimeoutException`, and passkey create/get ceremonies carry a two-minute timeout.
- An activation that fails after the keys are filed keeps them resumable: onboarding throws `OnboardingIncompleteException` with a handle whose `resume()` authenticates.
- The passkey pointer is stored in a namespace derived from the passkey; an enrollment asks for that namespace and the app's, and no longer for `atkeysv`.
- Secrets derived from the passkey are overwritten with zeroes once used and when the session closes.
- A registered passkey's `user.displayName` is its enrollment time (UTC, to the minute) and the enrollment's device name, cut to 64 UTF-8 bytes at a code point; it no longer carries the atSign.
- `passkeyLogin` refuses a remembered or pointed enrollment id outside `A-Za-z0-9_-` as a lost passkey, before any PKAM.
- JS bridge for `@atsign/at_client_web`: a web entry built by `tool/build.sh` (dart2js shipped; dart2wasm built as a check) exposing `passkeyEnroll`, `enrollSession` (OTP enrollment of a new browser, resolving once another device approves) and a `JsSession` over `AtClient`: `put`/`get` of strings and bytes, `delete`, `keys(regex)`, `notify` that resolves true only on delivery, and `subscribe`, which drops this session's own echoes and delivers only notifications whose key owner is the sending atSign, carried as `from`.
- Keys passed to the bridge keep their `public:`, `cached:` and no-namespace forms; a malformed key fails with `bad_key`.
- Pairing calls `otp`, `pendingEnrollments`, `approve` and `deny` for a session that holds `__manage`; other sessions get `unsupported`, and approving or denying an id that is not pending gives `enrollment_denied`.
- Exceptions reach JS as `{code, message}` with a stable `AtError` code; argument errors name the parameter and expected type, never the value received.
- `tool/serve.dart`: a development static server for the built bundles.
- New dependency `at_base2e15`: `get` decodes binary values to bytes.
