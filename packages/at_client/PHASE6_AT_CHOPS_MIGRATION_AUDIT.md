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
(AES) in two files: `encryption_util.dart` (sync AES methods) and
`aes_converter.dart` (streaming) — both blocked on the same gap (below).

### The AES blocker (the one thing left)

at_chops's byte-oriented `AESEncryptionAlgo.encrypt/decrypt` are **async**
(they `await` `better_cryptography`'s AES-CTR). `EncryptionUtil`'s
`encryptValue/decryptValue/encryptBytes/decryptBytes` and the `aes_converter`
sinks are **synchronous** with sync callers, so routing them through
`AESEncryptionAlgo` is an async breaking change that ripples to callers.

Options to close it (a real design decision, not a drop-in):
- at_chops exposes a **sync** AES surface. It already has a sync, String-only
  `StringAESEncryptor` (uses `package:encrypt` internally → byte-identical to
  `EncryptionUtil.encryptValue`), but **nothing sync for bytes** and nothing
  for chunked streaming. A sync bytes/streaming AES in at_chops would unblock
  both files without touching caller signatures.
- OR make the at_client AES methods async + sweep callers + run the full
  functional suite.

Either path is wire-sensitive (must stay byte-exact on already-stored
ciphertext) → its own commit, functional suite green at the boundary.

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

## 3. `encryption_util.dart` — RSA + md5 MIGRATED; AES remains

Central legacy AES/RSA util; output is **at-rest/on-wire compatible with
already-stored data and the atServer**.

| Method | Status |
|--------|--------|
| `encryptKey` / `decryptKey` (RSA) | **MIGRATED** → `RsaEncryptionAlgo` (settable `atPublicKey`/`atPrivateKey`). Framing verified byte-exact against crypton: `encrypt(String)=base64(encryptData(utf8(msg)))`, `decrypt(String)=utf8.decode(decryptData(base64(msg)))`. Compat test round-trips both directions (RSA PKCS1v15 is non-deterministic, so round-trip not byte-equality). |
| `md5CheckSum(data)` | **MIGRATED** → `DefaultHash().hash(utf8.encode(data))` (= `md5.convert(data).toString()`, identical). md5 also now wired in the factory. |
| `generateAESKey()` | remains on `encrypt` — random output, no wire risk; can move to `AtChopsUtil.generateSymmetricKey` when the AES block is tackled. |
| `generateIV()` / `getIV()` | remains on `encrypt` (`IV`). |
| `encryptValue`/`decryptValue`, `encryptBytes`/`decryptBytes` (AES) | **remains on `encrypt`** — blocked on the AES async/sync wall (see "The AES blocker" above). |

The `crypton` and `crypto` imports are gone; only `encrypt` (AES) is left.

## 4. `at_client_util.dart` — MIGRATED ✅

`signChallenge(challenge, privateKey)` (PKAM auth path) → `PkamSigningAlgo(
AtPkamKeyPair.create('', privateKey), HashingAlgoType.sha256).sign(...)`.
`PkamSigningAlgo` with sha256 calls the **identical** crypton
`RSAPrivateKey.createSHA256Signature` — byte-identical by construction
(signing reads only the private key, so the public-key slot is left empty).
A round-trip + byte-equality test (`at_client_util_test.dart`) verifies the
signature is valid under the public key and equals the legacy crypton output.
crypton import removed from this file.

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

## Remaining work (what's left)

Done: #1, #2, #4, and #3's RSA + md5. `crypto` and `crypton` are gone from
`lib/`. What's left is **only the AES sites**, both blocked on the same gap:

1. **Unblock AES in at_chops** — add a sync bytes AES (and ideally a chunked
   one) so `encryption_util`'s AES methods and `aes_converter` can route
   through at_chops without changing their sync caller signatures. This is the
   real prerequisite; do it before touching either consumer.
2. `encryption_util` AES (#3) — once (1) lands; gated by a byte-exact compat
   test against ciphertext produced by the current code, then the full
   functional suite (pluggable-encryption + legacy round-trip).
3. `aes_converter` (#5) — once (1) lands (streaming/no-padding variant).

Each lands as its own at_client commit, functional suite green at each
boundary (the refactor touches resource/wire lifecycle).

## Enforcement (Phase 6 step 6)

After the two AES sites land, add a grep/CI gate that fails if any
`package:crypton|crypto|encrypt|pointycastle|cryptography` import reappears in
`at_client/lib/`. Until the AES sites land, the gate would false-positive, so
it is sequenced last.
