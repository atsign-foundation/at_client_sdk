# OQ-P1 spike — WebAuthn PRF → HKDF-SHA256 → AES-GCM-256

Measures whether a browser + authenticator pair can hold the `at_client_wasm` key-envelope KEK via
the WebAuthn `prf` extension, and whether `largeBlob` is available as the fallback.

## Run

```sh
cd packages/at_client_wasm/spike/prf
python3 -m http.server 8080
```

Open `http://localhost:8080/` (localhost is a secure context; a LAN IP is not — use a tunnel with
TLS for phones).

1. **Register** — creates a discoverable credential with `prf.eval.first` and `largeBlob: preferred`.
2. **Seal** — `get` with `prf.eval.first` → HKDF(SHA-256, random salt, info `at_client_wasm/kek/v1`)
   → AES-GCM-256 → `{hkdfSalt, iv, ct}` into IndexedDB.
3. **Reload** the page.
4. **Unlock** — reads IndexedDB, repeats the `get`, decrypts, compares.
5. **Copy row** → paste into `RESULTS.md`. **Reset** clears localStorage + IndexedDB.

## Headless check (Chrome virtual authenticator)

DevTools → ⋮ → More tools → WebAuthn → Enable virtual authenticator environment →
protocol `ctap2`, transport `internal`, ✓ resident keys, ✓ user verification, ✓ **supports PRF**
(CDP: `WebAuthn.addVirtualAuthenticator` with `hasPrf: true`). Expect every column green.

## What decides the envelope

| Observation | Envelope `unlocks[].kind` |
|---|---|
| `getPrfFirstLen = 32` and `unlockedAfterReload = true` | `prf` |
| PRF absent, `largeBlobSupported = true` | `largeBlob` (store a random KEK, never a `CryptoKey`) |
| Neither | `passphrase` only on that platform |
