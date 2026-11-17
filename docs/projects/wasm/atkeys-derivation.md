# at-keys derivation — decisions

**Status:** ruled, and built (see "What is built" below) · 2026-10-15 · record layout re-ruled 2026-10-27 (K-10 pointer, K-11 document; K-6/K-8 superseded) · C4 (K-5) re-ruled and D (K-12, auth seed) ruled 2026-10-27; K-13 (fallbacks) ruled 2026-10-28
**Applied to:** [`browser-onboarding.md`](browser-onboarding.md) §2, BO-1, BO-2, BO-9 · circulate to Gary, Xavier and Jeremy S.
**Reconciles with:** `docs/projects/key-sources/prf-server-keys-blob.md` (PR #2427, merged to gkc's branch `gkc-published-vip-verifies-mldsa`, not on trunk)

## Summary

| # | Decision | Departs from |
|---|---|---|
| A | **Constant PRF salt**: `SHA-256("atsign:keys:lookup:v1")`; `get()` needs no atSign (recovery types it once, K-18) | Gary's model (salt derived from the atSign); pb5 `prfEvalInput(atSign)` |
| B | **One PRF call, then HKDF; no stored salt** | Gary's model (second PRF call with a random salt stored in the blob); browser-onboarding's `R` |
| C1 | **atSign in both HKDF labels** | — |
| C2 | **AES-256-GCM, AAD = the record's clear header** | #2295 (AAD = atSign, enrollmentId, version) |
| C4 | **Restored public keys must match the published ones before the restored keys are used**: after PKAM, before any encrypt or decrypt; a mismatch is a hard fail (K-5, re-ruled 2026-10-27) | — |
| D | **Third derivation, the auth seed**, seeds the enrollment's ML-DSA-65 APKAM key, never stored — the primary PKAM-key path (K-12). Fallbacks ruled by K-13 | #2295 (H-6 seed label) adopted; K-8's APKAM key generated and stored in the blob |
| — | Rejected: a per-write data key (C3) | #2295 |

## Derivation and record

```
salt  = SHA-256("atsign:keys:lookup:v1")
P     = WebAuthn get(prf.eval.first = salt)                 // one prompt
lookup = HKDF-SHA256(P, salt = ∅, info = "at_auth/custody/record-id/v1|<atSign>")   → 64 lowercase hex
kek    = HKDF-SHA256(P, salt = ∅, info = "at_auth/custody/kek/v1|<atSign>")
authSeed = HKDF-SHA256(P, salt = ∅, info = "at_auth/custody/auth-seed/v1|<atSign>")   → 32 bytes
ns     = HKDF-SHA256(P, salt = ∅, info = "at_auth/custody/ns/v1|<atSign>")         → 64 lowercase hex (K-17)
apkamKey = ML-DSA-65 keygen(seed = authSeed)                    // never stored (K-12)

record = { v: 2, typ, alg: "A256GCM", kdf: "HKDF-SHA256", iv: <96-bit random, per write>, ct }
AAD    = canonical JSON of the record without ct   (v, typ, alg, kdf, iv)
ct     = AES-256-GCM(kek, iv, plaintext, AAD)

pointer  = public:_<lookup>.<ns>@<atSign>         typ "eid"     plaintext = enrollmentId          no TTL, written once at enroll (K-10, K-17)
document = atkeys.<enrollmentId>.a.__e@<atSign>  typ "atkeys"  plaintext = @keys JSON without     read over PKAM by that enrollment (K-11)
                                                               the APKAM private key
```

- **Supersedes K-6 and K-8 (2026-10-27).** K-6's single TTL'd record holding the @keys becomes the pointer (no TTL, in the passkey's own namespace per K-17) plus the document. K-8's APKAM private key in the record is gone: the document holds no APKAM private key. The PKAM key is derived from the passkey (D, K-12); its fallbacks are ruled by K-13 (browser-onboarding §3.5, §3.6).
- `typ` in the AAD stops a pointer being opened as a document, or the reverse. Whether `v` changes with `typ` is open.

- `<atSign>` comes from the IndexedDB hint or, with the hint cleared, the user (K-18), so it is known before any derivation. It is the output of at_commons' `toAtsign()` (lowercase, `@` included, dots removed after the `@`, so `@ali.ce` is `@alice`), as UTF-8 bytes.
- `<atSign>` in the labels is canonical, as at_commons `toAtsign()` produces it: lowercase, leading `@`, dots removed. `@Alice`, `alice` and `@ali.ce` all derive the same keys.
- Test vector (`P` = bytes `00..1f`, atSign `@alice`):
  - salt `e5830b409db0e503af40c254598c41bf4e6ad6627ff185d311a9f446383ea620`
  - lookup `562dd8ceae1d04851c10847fea609250dc0c74d92af520a4ab96565bfea6c4b6`
  - ns `10781e72da94f814194f90c4c40d75d7b0b029d06253d40a610b0ad977b2d620`
  - kek `926e411c042496d783b7c01687562cc76b11cfe6fd683ddeeb285b7adfab83ce`
  - authSeed `b0e85850ef5407a914408bc6ccdc6a32baeb6446127275414199179a2cf79fc6`
  - Pinned by `packages/at_auth/test/passkey/passkey_key_deriver_test.dart` (`lookupHex and ns match the golden vectors for @alice and @bob`).
- All four labels have the form `at_auth/custody/<name>/v1` (`record-id`, `kek`, `auth-seed`, `ns`). The Dart (`at_auth`) and WebCrypto (`at_client_wasm`) derivations both take them from the `at_auth` constants, so they cannot drift. These label strings are canonical. They replace the unversioned `atkeys-record-id`, `atkeys-kek` and `atkeys-ns` and, before them, `atkeys/lookup` and `atkeys/blob`; only the auth-seed label is unchanged, so its vector is too. A record sealed or pointer written under an unversioned label does not open under these.

## Why

### A — constant salt

`get()` runs locally **before** any network call. The atSign, from the hint or typed by the user (K-18), then drives the root lookup, the unauthenticated `lookup:` (no `from:`), and finally `from:` + PKAM. The salt has to be in the `get()` request, so it can't depend on an atSign that isn't known yet. PRF output is already unique per credential.

### B — no stored salt

| Where a random `R` could go | Result |
|---|---|
| PRF input (two calls) | `R` sits outside the ciphertext, so the server controls it. Setting `R` = the predictable salt makes the passkey return the lookup key, which the server knows because it's the record name. The server can then forge a record the client accepts. It also costs a second prompt. |
| HKDF salt | Harmless but redundant. `P` is already 256 uniform bits, and salts defend low-entropy inputs. |

Freshness per write comes from the random IV.

### D — auth seed

A separate label keeps the APKAM key independent of the lookup key (which the server knows) and of the kek. The key is derived, not stored, so the document holds no key that can sign as the enrollment, and a cleared browser loses no key the passkey cannot re-derive. The pointer only names the enrollment: a swapped or deleted pointer makes PKAM fail, which is denial of recovery, not disclosure.

### C — hardening

| | Stops |
|---|---|
| C1 atSign in labels | Linking or splicing records if a passkey is ever paired with two atSigns |
| C2 AAD = clear header | Downgrade attacks via edits to `v`, `alg` or `kdf` |
| C4 public-key check | **Partial rollback**: the server replays an older valid document whose keys have since been rotated, without rolling back the published keys too. Runs after PKAM and after the document is opened, before the restored keys are used. Does not stop a compromised atServer that rolls back the document and the published keys together, nor a stale-but-valid document whose public keys are unchanged |
| C3 per-write data key (rejected) | Nothing here. Its job is letting several passkeys unlock one shared key, the `unlocks[]` pattern this design removes. |

## Cost of changing later

| Point | Cost |
|---|---|
| A — salt | High. A return flow can migrate in one prompt with `prf.eval.second`; devices that next appear via recovery must re-enroll. |
| D — auth-seed label | High. A new label derives a different APKAM key, so every enrollment must be redone. |
| B, C1 — labels | Low. `P` comes back on every open: derive under the old labels, decrypt, rewrite, delete the old record. |
| C2 — record format | Low. `v` migrates on the next open. |

## What is built

| Item | Behaviour |
|---|---|
| API | `onboardNewAtSign`, `passkeyLogin` (`atSign` required), `prfSupported`, each in `at_client_wasm_web.dart`; `onboardNewAtSign` and `passkeyLogin` take an optional `SessionTransportOptions` |
| Derivation | `PasskeyPrf` runs the one PRF call; `PasskeyVault` holds the derived record key, pointer lookup, pointer namespace and auth seed, and seals and opens records |
| Exceptions | `PrfUnavailableException`, `PasskeyLostException`, `PublicKeyMismatchException`, `MissingAtKeysDocumentException`, `OnboardingIncompleteException`, `SetupLockTimeoutException`; a refused PKAM is always `PasskeyLostException` with `PkamRefusedException` as its cause |
| Setup lock | Per canonical atSign, held across onboarding; login takes it only with a pending record, with no saved hints, or for the stale-hints retry |
| Write order | Document first, then the pointer |
| APKAM key | `authSeed` seeds it on every open; never stored |
| Key store | `AtServerAtKeysIo` reads and writes the sealed document through the enrollment's own connection |
| `user.id` | Random; the atSign is never in it (K-18) |

v1 limits are listed in [`browser-onboarding.md`](browser-onboarding.md) §7.
