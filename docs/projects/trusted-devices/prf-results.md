# WebAuthn PRF on the web — OQ-P1 results

* **Status:** Decided — `prf` is the passkey unlock kind; iOS row open
* **Last Updated:** 2026-09-25
* **Spike:** `packages/at_client_wasm/spike/prf/` (raw rows in `RESULTS.md`)

## Question

Can a browser passkey hold the key that unlocks `at_client_wasm`'s at-rest key envelope, through
the WebAuthn `prf` extension? If not, is `largeBlob` there as a fallback?

## Method

One page, per browser × passkey provider: register with `prf.eval.first`, `get` with the same salt,
HKDF-SHA256 → AES-GCM-256 seal into IndexedDB, **reload**, `get` again, open. A pass is 32 bytes on
both ceremonies and a plaintext match after the reload.

## Results

| Browser | OS | Passkey provider | caps `prf` | create / get bytes | `largeBlob` | Opens after reload |
|---|---|---|---|---|---|---|
| Chrome 153 | macOS | Google Password Manager (Touch ID) | ✓ | 32 / 32 | supported | ✓ |
| Safari 26.6 | macOS | iCloud Keychain | ✓ | 32 / 32 | not reported | ✓ |
| Brave (Chromium 152) | macOS | Browser-profile passkey (not in iCloud Keychain) | ✓ | 32 / 32 | unsupported | ✓ |
| Brave (Chromium 153) | Android | Google Password Manager | ✓ | 32 / 32 | not reported | ✓ |

Not yet run: Safari on iOS (iCloud Keychain), Firefox, Edge / Windows Hello, security keys,
third-party providers (1Password, Bitwarden, Samsung Pass).

## Decision

| # | Decision | Because |
|---|---|---|
| 1 | `prf` is the envelope's passkey unlock kind; envelope `v: 1` stands as built in #2267 | Every provider tested returns a stable 32-byte output |
| 2 | No `largeBlob` unlock kind | Supported on one row of four, and never the only way in |
| 3 | A generated passphrase stays the recovery unlock | Covers a provider without PRF and the loss of every passkey |
| 4 | Seal at registration when `create` returns `prf.results.first`; otherwise `get` once | `create` returned the output on all four rows — one ceremony instead of two |
| 5 | Detect with `getClientCapabilities()['extension:prf']`, then trust the ceremony's result | The capability was true everywhere, but a provider chosen in the dialog can still lack PRF |
| 6 | The PRF eval input is derived, `SHA-256("at_client_wasm/prf-eval/v1\|" + atSign)`; the credential ID stays in local storage only, and a new device finds the passkey as a discoverable credential | The server copy is world-readable, so it carries ciphertext and KDF salts only; a synced passkey reproduces the eval input from the atSign |
| 7 | The portal seals the `passphrase` unlock only; the app adds a `prf` unlock after the first open and writes the envelope back to the server | The portal is a different RP ID, so it cannot produce the app's PRF output |

## Consequences for trusted devices

* A synced passkey's PRF seed syncs with it (Google Password Manager, iCloud Keychain), so the
  same passkey yields the same output on each of the owner's devices.
* That makes the envelope portable across the owner's devices, and makes PRF **no evidence of
  which device** is connecting. A registered device ID must come from device-bound material — a
  non-extractable WebCrypto key or a hardware security key — never from a synced passkey's PRF.
* The Brave macOS row is the one device-bound passkey observed; it does not follow the owner to
  another device.

## Open

* **Safari on iOS** — the only engine iOS allows; decision 1 is provisional there until it passes.
* **Cross-device output** — the same synced passkey unlocking on a second device is inferred from
  how providers sync, not measured. The spike keeps its credential record per browser; measuring
  it needs an export/import of that record and one hostname for both devices.
