# at-keys derivation — decisions

**Status:** decided · 2026-10-15 · record layout re-ruled 2026-10-27 (K-10 pointer, K-11 document; K-6/K-8 superseded) · gate (c) and K-5′ proposed
**Applied to:** [`browser-onboarding.md`](browser-onboarding.md) §2, BO-1, BO-2, BO-9 · circulate to Gary, Xavier and Jeremy S.
**Reconciles with:** `docs/projects/key-sources/prf-server-keys-blob.md` (PR #2295)

## Summary

| # | Decision | Departs from |
|---|---|---|
| A | **Constant PRF salt**: `SHA-256("atsign:keys:lookup:v1")`; recovery is typing-free | Gary's model (salt derived from the atSign); pb5 `prfEvalInput(atSign)` |
| B | **One PRF call, then HKDF; no stored salt** | Gary's model (second PRF call with a random salt stored in the blob); browser-onboarding's `R` |
| C1 | **atSign in both HKDF labels** | — |
| C2 | **AES-256-GCM, AAD = the record's clear header** | #2295 (AAD = atSign, enrollmentId, version) |
| C4 | **Restored public keys must match the published ones before PKAM**. Under K-11 the document arrives after PKAM; the rewording K-5′ ("before the keys are used") is proposed | — |
| — | Rejected: a per-write data key (C3) | #2295 |

## Derivation and record

```
salt  = SHA-256("atsign:keys:lookup:v1")
P     = WebAuthn get(prf.eval.first = salt)                 // one prompt
lookup = HKDF-SHA256(P, salt = ∅, info = "atkeys-record-id|<atSign>")   → 64 lowercase hex
kek    = HKDF-SHA256(P, salt = ∅, info = "atkeys-kek|<atSign>")

record = { v: 2, typ, alg: "A256GCM", kdf: "HKDF-SHA256", iv: <96-bit random, per write>, ct }
AAD    = canonical JSON of the record without ct   (v, typ, alg, kdf, iv)
ct     = AES-256-GCM(kek, iv, plaintext, AAD)

pointer  = public:_<lookup>.atkeysv@<atSign>     typ "eid"     plaintext = enrollmentId          no TTL, written once at enroll (K-10)
document = atkeys.<enrollmentId>.a.__e@<atSign>  typ "atkeys"  plaintext = @keys JSON without     read over PKAM by that enrollment (K-11)
                                                               the APKAM private key
```

- **Supersedes K-6 and K-8 (2026-10-27).** K-6's single TTL'd record holding the @keys becomes the pointer (same name, no TTL) plus the document. K-8's PCAM private key in the record is gone: the document holds no APKAM private key. Where the PKAM key comes from (a passkey-derived ML-DSA-65 key) is part of gate (c), proposed, not ruled.
- `typ` in the AAD stops a pointer being opened as a document, or the reverse. Whether `v` changes with `typ` is open.

- `<atSign>` comes from `userHandle`, so it is known before any derivation.
- `<atSign>` in the labels is canonical, as at_commons `toAtsign()` produces it: lowercase, leading `@`, dots removed. `@Alice`, `alice` and `@ali.ce` all derive the same keys.
- Test vector (`P` = bytes `00..1f`, atSign `@alice`):
  - salt `e5830b409db0e503af40c254598c41bf4e6ad6627ff185d311a9f446383ea620`
  - lookup `7086a5038ed92fcd20309c479df67581a64cf9f8caf802ef81e7ecec8e4272fe`
  - kek `338114674b5a98898fe30e20b4e29e96907ac6ec58b615bc0a298e759cd520b0`
- These label strings are canonical. They replace `atkeys/lookup` and `atkeys/blob`.

## Why

### A — constant salt

`get()` runs locally **before** any network call and returns `userHandle` = atSign. That atSign then drives the root lookup, the unauthenticated `lookup:` (no `from:`), and finally `from:` + PKAM. The salt has to be in the `get()` request, so it can't depend on an atSign that isn't known yet. PRF output is already unique per credential.

### B — no stored salt

| Where a random `R` could go | Result |
|---|---|
| PRF input (two calls) | `R` sits outside the ciphertext, so the server controls it. Setting `R` = the predictable salt makes the passkey return the lookup key, which the server knows because it's the record name. The server can then forge a record the client accepts. It also costs a second prompt. |
| HKDF salt | Harmless but redundant. `P` is already 256 uniform bits, and salts defend low-entropy inputs. |

Freshness per write comes from the random IV.

### C — hardening

| | Stops |
|---|---|
| C1 atSign in labels | Linking or splicing records if a passkey is ever paired with two atSigns |
| C2 AAD = clear header | Downgrade attacks via edits to `v`, `alg` or `kdf` |
| C4 public-key check | **Rollback**: the server replays an older valid document whose keys have since been rotated |
| C3 per-write data key (rejected) | Nothing here. Its job is letting several passkeys unlock one shared key, the `unlocks[]` pattern this design removes. |

## Cost of changing later

| Point | Cost |
|---|---|
| A — salt | High. A return flow can migrate in one prompt with `prf.eval.second`; devices that next appear via recovery must re-enroll. |
| B, C1 — labels | Low. `P` comes back on every open: derive under the old labels, decrypt, rewrite, delete the old record. |
| C2 — record format | Low. `v` migrates on the next open. |
