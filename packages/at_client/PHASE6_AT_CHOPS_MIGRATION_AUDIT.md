# Phase 6 — at_client crypto/hashing migration audit

**Outcome (whole phase):** every `at_` package depends on **at_chops alone**
for crypto and hashing. at_chops stays the one place that imports the
primitive libraries (`crypton`, `crypto`, `encrypt`, `pointycastle`,
`cryptography`); each *consumer* routes through at_chops's public API.

This doc is the at_client slice (Phase 6 step 3). It enumerates every direct
non-at_chops crypto/hashing import in `lib/`, maps each call to its at_chops
replacement, and classifies it **MATCHED** (drop-in), **DIVERGED** (needs a
byte-compat check before swapping), or **MISSING** (at_chops has no
equivalent yet).

## at_chops surface relied on

Added in Phase 6 step 1 (committed in the at_chops package):

- `HmacSha256.compute(key, data)` — RFC 2104, 32 raw bytes.
- `HkdfSha256.deriveKey(ikm, {salt, info, length})` — RFC 5869, vector-tested
  (`test/hkdf_algo_test.dart`: RFC 5869 cases 1–3, RFC 4231 HMAC cases 1–2).
- `SHA256HashingAlgo()` (hex `String`) + `AtChops.hashWith(HashingAlgoType.sha256)`.
- `AtChops.hashWith(HashingAlgoType.md5)` now wired (was previously unmapped
  in the factory → threw "Unsupported hashing algorithm").

Pre-existing and relied on for the deeper sites:
`AtChopsUtil.generateSymmetricKey(EncryptionKeyType.aes256)`,
`AtChopsUtil.generateRandomIV(length)`, `AESEncryptionAlgo` (AES-CTR + PKCS7),
`AesGcm256EncryptionAlgo`, `RsaEncryptionAlgo`, `PkamSigningAlgo` /
`DefaultSigningAlgo`.

## Site inventory

| # | File | Lib(s) | Status |
|---|------|--------|--------|
| 1 | `secret_sharing/client_key_package.dart` | `crypto` (sha256) | **MIGRATED** |
| 2 | `secret_sharing/pairwise_group.dart` | `crypto` (sha256, Hmac/HKDF) | **MIGRATED** |
| 3 | `util/encryption_util.dart` | `crypton`, `encrypt`, `crypto` | **DEFERRED** (core wire path) |
| 4 | `util/at_client_util.dart` | `crypton` (RSA sign) | **DEFERRED** (signature bytes) |
| 5 | `converters/encryption/aes_converter.dart` | `encrypt` (AES-CTR, streaming) | **DEFERRED** (MISSING streaming API) |

---

## 1. `client_key_package.dart` — MIGRATED ✅

`PackageKey.computeKid(pub)` = first 8 bytes (16 hex chars) of `sha256(pub)`.

- **Was:** `sha256.convert(utf8.encode(pub)).bytes.take(8)…toRadixString(16)…`
- **Now:** `SHA256HashingAlgo().hash(utf8.encode(pub)).substring(0, 16)`
  (full hex digest, first 16 chars = first 8 bytes). **MATCHED** — identical
  output; `computeKid` stays synchronous (the concrete class's `hash` returns
  `String`, not `FutureOr`), which the constructor initializer requires.

## 2. `pairwise_group.dart` — MIGRATED ✅

- `kidOf(keyBytes)`: same pattern as above → `SHA256HashingAlgo().hash(...).substring(0,16)`. **MATCHED.**
- `export(label, length)` HKDF-SHA256: removed the hand-rolled
  `_hkdfSha256`/`hkdfSha256` (RFC 5869 over `package:crypto`'s `Hmac`) →
  `HkdfSha256.deriveKey(cur.key, salt:, info:, length:)`. **MATCHED** — same
  RFC 5869 construction; at_chops carries the vector tests now, so the
  pairwise-layer `hkdfSha256 is deterministic` unit test was dropped
  (redundant); `export`'s determinism is still covered by the
  `export is deterministic by (label)…` test.

Both files now import only `package:at_chops/at_chops.dart` for crypto; the
Phase-3 "rides `package:crypto`" note in the roadmap is **closed**.

---

## 3. `encryption_util.dart` — DEFERRED (core wire path)

Already carries `//#TODO Replace calls … with at_chops methods and move this
class to test folder in next major release`. This is the central legacy AES/RSA
util; output is **at-rest and on-wire compatible with already-stored data and
the atServer**, so each swap needs a byte-exact compat test, not just a green
unit run.

| Method | at_chops replacement | Class |
|--------|----------------------|-------|
| `generateAESKey()` | `AtChopsUtil.generateSymmetricKey(EncryptionKeyType.aes256).key` | MATCHED |
| `generateIV()` / `getIV()` | `AtChopsUtil.generateRandomIV(len)` / `InitialisationVector` | MATCHED |
| `md5CheckSum(data)` | `AtChops.hashWith(HashingAlgoType.md5).hash(utf8.encode(data))` | MATCHED (md5 now wired in the factory) |
| `encryptKey` / `decryptKey` (RSA) | `RsaEncryptionAlgo` — wraps the same `crypton` RSA under the hood, so byte-compatible | DIVERGED — verify PKCS1v15 framing matches |
| `encryptValue`/`decryptValue`, `encryptBytes`/`decryptBytes` (AES) | `AESEncryptionAlgo` | **DIVERGED** — `encrypt`'s default AES (SIC/CTR **with PKCS7**) vs at_chops `AESEncryptionAlgo` (AES-CTR + PKCS7 via `cryptography`); modes look equivalent but must be proven byte-exact on existing ciphertext before swapping |

## 4. `at_client_util.dart` — DEFERRED (signature bytes)

`signChallenge(challenge, privateKey)` = `RSAPrivateKey.createSHA256Signature`
(crypton), base64-encoded. Used in the PKAM auth path.

- at_chops replacement: `PkamSigningAlgo` / `DefaultSigningAlgo` (RSA-SHA256).
- **DIVERGED** — the produced signature bytes must be **byte-identical** so the
  atServer's existing verify accepts them. Needs a round-trip vector
  (sign here, verify with the legacy path) before swapping.

## 5. `aes_converter.dart` — DEFERRED (MISSING streaming API)

`AESEncrypter`/`AESDecrypter` are `Converter<List<int>,List<int>>` with
`ChunkedConversionSink` support, AES with **`padding: null`** (raw CTR, no
PKCS7) — used by the streaming value codec.

- **MISSING** in at_chops: no streaming/chunked AES converter, and no
  no-padding AES-CTR one-shot (its `AESEncryptionAlgo` always PKCS7-pads).
- Options: (a) add a no-padding streaming AES surface to at_chops; or (b) keep
  this converter as a thin internal that calls an at_chops no-padding one-shot
  per buffer. Either way this is the largest of the three and needs its own
  design step. Defer until 3–4 are settled.

---

## Recommended order for the deferred sites

1. `at_client_util.signChallenge` (#4) — smallest, single method; gated by a
   sign-here/verify-legacy round-trip test.
2. `encryption_util` MATCHED rows (#3: key/IV gen, md5) — zero wire risk.
3. `encryption_util` AES + RSA (#3 DIVERGED) — gated by a byte-exact compat
   test against ciphertext produced by the current code; then run the full
   functional suite (pluggable-encryption + legacy round-trip).
4. `aes_converter` (#5) — needs the at_chops streaming/no-padding decision
   first.

Each lands as its own at_client commit, functional suite green at each
boundary (the refactor touches resource/wire lifecycle).

## Enforcement (Phase 6 step 6)

After all five sites are migrated, add a grep/CI gate that fails if any
`package:crypton|crypto|encrypt|pointycastle|cryptography` import reappears in
`at_client/lib/`. Until #3–#5 land, the gate would false-positive, so it is
sequenced last.
