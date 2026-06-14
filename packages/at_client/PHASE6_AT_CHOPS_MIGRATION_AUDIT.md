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
| 3 | `util/encryption_util.dart` | ~~`crypton`~~, ~~`crypto`~~, `encrypt` | **RSA + md5 MIGRATED; AES remains** (async wall) |
| 4 | `util/at_client_util.dart` | `crypton` (RSA sign) | **MIGRATED** |
| 5 | `converters/encryption/aes_converter.dart` | `encrypt` (AES-CTR, streaming) | **DEFERRED** (MISSING streaming API) |

**`package:crypto` and `package:crypton` are now entirely absent from
`at_client/lib/`.** The only remaining direct crypto import is `package:encrypt`
(AES) in two files: `encryption_util.dart` and `aes_converter.dart`.

### The AES sites: deprecated-only / test-only — DECISION: defer to v4

A call-graph trace (2026-06-14) shows the AES **cipher** is not reachable from
any live production path:

| AES site | Reachable from |
|----------|----------------|
| `EncryptionUtil.encryptBytes`/`decryptBytes` | `EncryptionService.encrypt/decryptStream` → only `@Deprecated` `AtClientImpl.stream()` ("removed in v4") + the deprecated file methods |
| `EncryptionUtil.encryptValue`/`decryptValue` (String) | **zero production callers**; used only as legacy-ciphertext helpers in ~7 test files |
| `aes_converter.dart` (`AESEncrypter`/`AESDecrypter`/`AESCodec`/sinks) | only `encrypt/decryptFileInChunks` → `@Deprecated` `uploadFile`/`shareFiles`/`downloadFile`/`reuploadFiles` ("moved to app layer") |
| `EncryptionService`, `StreamNotificationHandler` | only the deprecated `stream()`/file methods |

The single live `package:encrypt` use was `EncryptionUtil.generateIV()` (random
`ivNonce`), now routed to `AtChopsUtil.generateRandomIV` (non-breaking — random
output). `generateAESKey()` is reachable only from the deprecated
`EncryptionService`.

**Decision (option 2):** at_client is **3.13.x**; the deprecations are tagged
for **v4** removal, so deleting them now would be a semver-major break. We do
**not** migrate the deprecated AES cipher onto at_chops (that would be polishing
code slated for deletion, and at_chops's byte AES is async anyway while these
are sync). Instead:

- The live path is at_chops-clean (`generateIV` routed).
- The AES cipher stays on `package:encrypt` in `encryption_util.dart` +
  `aes_converter.dart` **until the v4 removal** of the deprecated stream/file
  methods, at which point this code is deleted (or `EncryptionUtil` moves to a
  test helper, per its own TODO) rather than migrated.
- The Phase 6 import gate (step 6) **carves out these two files** until v4.

When v4 is cut: delete the deprecated `AtClientImpl` stream/file methods +
their spec decls, `EncryptionService`, `StreamNotificationHandler`,
`aes_converter.dart`; move `EncryptionUtil`'s remaining cipher helpers to a
test-only helper. That removes `package:encrypt` from `at_client/lib`
entirely — no at_chops AES work required.

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

## 3. `encryption_util.dart` — RSA + md5 + generateIV MIGRATED; AES quarantined

Central legacy AES/RSA util; output is **at-rest/on-wire compatible with
already-stored data and the atServer**.

| Method | Status |
|--------|--------|
| `encryptKey` / `decryptKey` (RSA) | **MIGRATED** → `RsaEncryptionAlgo` (settable `atPublicKey`/`atPrivateKey`). Framing verified byte-exact against crypton: `encrypt(String)=base64(encryptData(utf8(msg)))`, `decrypt(String)=utf8.decode(decryptData(base64(msg)))`. Compat test round-trips both directions (RSA PKCS1v15 is non-deterministic, so round-trip not byte-equality). |
| `md5CheckSum(data)` | **MIGRATED** → `DefaultHash().hash(utf8.encode(data))` (= `md5.convert(data).toString()`, identical). md5 also now wired in the factory. |
| `generateIV()` | **MIGRATED** → `base64Encode(AtChopsUtil.generateRandomIV(length).ivBytes)`. The one live `package:encrypt` use; random output → non-breaking. |
| `generateAESKey()`, `getIV()` | stay on `encrypt` — reachable only from the deprecated/quarantined AES cipher below. |
| `encryptValue`/`decryptValue`, `encryptBytes`/`decryptBytes` (AES) | **QUARANTINED on `encrypt`** until the v4 removal (deprecated-only / test-only — see "The AES sites" above). |

`crypton` and `crypto` imports gone; `encrypt` remains for the quarantined AES.

## 4. `at_client_util.dart` — MIGRATED ✅

`signChallenge(challenge, privateKey)` (PKAM auth path) → `PkamSigningAlgo(
AtPkamKeyPair.create('', privateKey), HashingAlgoType.sha256).sign(...)`.
`PkamSigningAlgo` with sha256 calls the **identical** crypton
`RSAPrivateKey.createSHA256Signature` — byte-identical by construction
(signing reads only the private key, so the public-key slot is left empty).
A round-trip + byte-equality test (`at_client_util_test.dart`) verifies the
signature is valid under the public key and equals the legacy crypton output.
crypton import removed from this file.

## 5. `aes_converter.dart` — QUARANTINED until v4

`AESEncrypter`/`AESDecrypter` are `Converter<List<int>,List<int>>` with
`ChunkedConversionSink` support, AES `padding: null` (raw CTR) — used **only**
by the deprecated `encrypt/decryptFileInChunks` → `@Deprecated`
`uploadFile`/`shareFiles`/`downloadFile`/`reuploadFiles`. Stays on
`package:encrypt` until those methods are removed in v4, then deleted.

---

## Remaining work (what's left)

at_client `lib/` is **crypto-clean on all live paths**. `crypto` and `crypton`
are gone; `encrypt` remains only in the two quarantined files
(`encryption_util.dart` AES cipher, `aes_converter.dart`), both reachable in
production only from `@Deprecated` stream/file methods slated for v4 removal.

- **No further at_client AES migration** (decision: option 2 — defer to v4).
  When v4 is cut, delete the deprecated stream/file methods + `EncryptionService`
  + `StreamNotificationHandler` + `aes_converter.dart`, and move
  `EncryptionUtil`'s cipher helpers to a test helper — `package:encrypt` then
  leaves `lib/` with no at_chops AES work needed.
- Phase 6 then continues with the **other consumer packages** (at_lookup,
  at_utils, at_auth, at_onboarding_cli, flutter) — steps 4–5.

## Enforcement (Phase 6 step 6)

The grep/CI gate (fails on any `crypton|crypto|encrypt|pointycastle|
cryptography` import in a consumer's `lib/`) is sequenced after steps 4–5.
For at_client it must **carve out** the two quarantined files
(`util/encryption_util.dart`, `converters/encryption/aes_converter.dart`) until
the v4 removal deletes them — a documented, time-boxed exception, not an open
hole.
