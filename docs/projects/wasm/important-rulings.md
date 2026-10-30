# Important rulings — wasm lane

**Status:** index only, kept current as rulings land · the binding text lives in [`decisions.md`](decisions.md)

| ID | Ruling in one line | Date | Link |
|---|---|---|---|
| K-5 | Restored public keys must match the published `publickey` after PKAM; mismatch is a hard fail | 2026-10-15, re-ruled 2026-10-27 | [K-5](decisions.md#browser-at-keys-custody--k-1k-13) |
| K-10 | TTL-less public pointer `_<lookupHex>.atkeysv` seals the enrollmentId | 2026-10-27 | [K-10](decisions.md#browser-at-keys-custody--k-1k-13) |
| K-11 | Sealed @keys live in a private per-enrollment document, read over PKAM | 2026-10-27 | [K-11](decisions.md#browser-at-keys-custody--k-1k-13) |
| K-12 | The PKAM key is derived from the passkey, never stored | 2026-10-27 | [K-12](decisions.md#browser-at-keys-custody--k-1k-13) |
| K-13 | K-12 fallbacks: passphrase-sealed server record for no-PRF, no recovery for a lost passkey, IndexedDB hint only, second passkey is its own enrollment, no key expiry | 2026-10-28 | [K-13](decisions.md#browser-at-keys-custody--k-1k-13) |
| R-a | An approver reinstates a revoked enrollment with `enroll:unrevoke` | 2026-10-27 | [Revocation](decisions.md#browser-at-keys-custody--k-1k-13) |
| D-15 | Browser reaches the atServer on the direct path; the proxy is dev-only | 2026-09-13, amended 2026-10-23 | [D-15](decisions.md#d-15--the-transport-is-the-third-leg-of-the-platform-bundle-injected-at-the-doors-2026-09-13) |
| D-26 | Browser SQLite storage is SimpleOPFS, one directory per (atSign, enrollmentId) | 2026-10-13 | [D-26](decisions.md#d-26--browser-sqlite-storage-is-simpleopfs-one-directory-per-atsign-enrollmentid-w4-resolved-2026-10-13) |
