## 4.0.0
- breaking: remove the deprecated `AtChops`/`AtChopsImpl` facade, `AtChopsKeys`, `AtChopsUtil`, `AtEncrypted`, and `AtHashingAlgorithmFactory` — construct and call the algorithm classes directly (e.g. `RsaSigningAlgo`, `AesGcm256EncryptionAlgo`, `Sha256HashingAlgo`), and generate IVs with `InitialisationVector.random(length)`
- breaking: remove the deprecated result/input/metadata types `AtSigningInput`, `AtSigningVerificationInput`, `AtSigningMode`, `AtSigningResult`, `AtSigningResultType`, `AtSigningMetaData`, `AtEncryptionResult`, `AtEncryptionResultType`, and `AtEncryptionMetaData` — use the algorithm result bytes directly with your own metadata
- breaking: remove all key-pair wrapper classes (`RsaKeyPair`, `X25519KeyPair`, `MlDsa65KeyPair`, `MlKem768KeyPair`, `XWingKeyPair`) and the deprecated `At*KeyPair` classes, along with the `AbstractKeyPair`/`AsymmetricKeyPair` hierarchy and the `RawKeyPairBytes` mixin — generate key material directly from each algorithm's `generateKeyPair()` (which returns raw `Uint8List` public/secret keys) and base64-encode into `AtPublicKey`/`AtPrivateKey` if you need the SDK's string form
- breaking: `RsaSigningAlgo`, `EccSigningAlgo`, and `Ed25519SigningAlgo` now implement the stateless `AtSignatureAlgorithm` interface — their old stateful constructors/setters and `sign`/`verify` methods are replaced by `generateKeyPair()`/`signBytes()`/`verifyBytes()` with key material passed per call as raw bytes (`RsaSigningAlgo` takes `hashingAlgoType`/`keySize` as named constructor parameters). Key bytes are raw: Ed25519 uses the 32-byte seed/public key, ECC uses the 32-byte scalar and 65-byte uncompressed point, RSA uses DER. Also removes the deprecated `AtSigningAlgorithm` interface and the `DefaultHash`/`DefaultSigningAlgo`/`PkamSigningAlgo` compatibility wrappers
- breaking: `AtSignatureAlgorithm.verifyBytes` returns `Future<void>` and throws `AtSigningVerificationException` on a failed verification — a wrong key, a tampered message, or a forged signature — instead of returning `false`. A failed verification is an error, not a result, and the boolean was too easy to ignore; every other at_chops interface (`decrypt`, `hash`, `decapsulate`, `pqOpen`) already signalled failure by throwing. All five implementations follow suit, and the ML-DSA FFI backend now distinguishes a libcrypto fault (`StateError`) from a bad signature. Malformed key or signature *bytes* remain caller errors and still surface as `ArgumentError`/`RangeError`. External implementers must update their override; callers replace `if (await algo.verifyBytes(...))` with a bare `await` plus a `catch` where they need one
- breaking: the encryption interfaces are now stateless — `SymmetricEncryptionAlgorithm` and `ASymmetricEncryptionAlgorithm` take the key as a second positional argument on `encrypt`/`decrypt`. Implementers hold no key state, so a single instance is safe to share
- breaking: `iv` is now a **required** named parameter on `SymmetricEncryptionAlgorithm.encrypt`/`decrypt` (and on `AesCtrEncryptionAlgo`, `AesGcm256EncryptionAlgo`, `AesGcm256FfiAlgo`). Nothing generates an IV for you and nothing returns a generated one, so the caller must own it; an IV of the wrong length is rejected with `AtEncryptionException`/`AtDecryptionException`. AES-CTR call sites that relied on the implicit all-zeroes IV must now pass `InitialisationVector.legacy()` explicitly
- chore: flatten `lib/src/algorithm/**` up one level to `lib/src/**` — e.g. `src/algorithm/encryption/aes_gcm.dart` is now `src/encryption/aes_gcm.dart`. All of it is under `src/`, so only code reaching past the public barrels (`at_chops.dart`, `at_chops_ffi.dart`, `types.dart`) is affected
- breaking: remove the generic `AtEncryptionAlgorithm<T, V>` base interface — it was never used as a type and both subtypes pinned `T`/`V` to `Uint8List`. `SymmetricEncryptionAlgorithm` and `ASymmetricEncryptionAlgorithm` are now standalone interfaces, which is what lets the symmetric one require `iv`
- breaking: `RsaEncryptionAlgo` loses `fromKeyPair` and the `atPublicKey`/`atPrivateKey` fields — pass raw DER bytes per call: `rsa.encrypt(data, publicKey)` / `rsa.decrypt(data, privateKey)`. The "public/private key not set" exceptions are gone with them
- breaking: `AesGcm256EncryptionAlgo` and `AesGcm256FfiAlgo` take the key per call instead of at construction; `AesGcm256FfiAlgo.fromLib(lib, key)` becomes `fromLib(lib)` and `AesGcm256EncryptionAlgo(key)` becomes `AesGcm256EncryptionAlgo()`
- breaking: `AtPqc.aesGcm256` is a static field rather than a factory method, matching `AtPqc.xWing`/`AtPqc.mlDsa65` — the key is no longer needed at construction
- breaking: `AESEncryptionAlgo` is renamed `AesCtrEncryptionAlgo` and moved to `src/encryption/aes_ctr.dart` — it takes the AES key length in bytes (16/24/32) as its constructor argument and the raw key bytes per `encrypt`/`decrypt` call, so `AESEncryptionAlgo(aesKey).encrypt(data, iv: iv)` becomes `AesCtrEncryptionAlgo(32).encrypt(data, base64Decode(aesKey.key), iv: iv)`. A key whose length differs from the configured one is rejected. The `AesCtrFactory` key-length dispatch is folded into that constructor and the class is removed
- breaking: add `generateKey()` to `SymmetricEncryptionAlgorithm` — returns a fresh key of whatever length the implementation requires (`AesGcm256EncryptionAlgo`/`AesGcm256FfiAlgo` always 32 bytes; `AesCtrEncryptionAlgo` its configured `keyLengthBytes`), so a caller holding the interface never has to know the length. Replaces the removed `AESKey.generate`. External `implements` users must add it
- breaking: remove `StringAESEncryptor` — encode to bytes and use `AesCtrEncryptionAlgo` (or `AesGcm256EncryptionAlgo`, which authenticates) directly
- breaking: remove the misnamed `Ed25519Key` class (it was an AES symmetric key, not an Ed25519 key) — use `AESKey`
- breaking: remove the deprecated stateful `secretKey` setter, `sign`, and `verify` on `MlDsa65PureDartAlgo` and `MlDsa65FfiAlgo` — use `signBytes`/`verifyBytes` with explicit key material (or `AtPqc.mlDsa65` typed as `AtSignatureAlgorithm`)
- breaking: remove `AtKeysCrypto` (atKeys-file encrypt/decrypt) — it now lives in `at_auth`
- breaking: add `AtAlgorithm`, the sealed supertype every algorithm interface now implements — `AtSignatureAlgorithm`, `SymmetricEncryptionAlgorithm`, `ASymmetricEncryptionAlgorithm`, `AtHashingAlgorithm`, `AtKemAlgorithm`, and `AtKeyAgreementAlgorithm`. It gives downstream code (at_server) one type that holds any at_chops algorithm, and because it is sealed a `switch` over those six families is exhaustive with no default arm. Sealing is not transitive, so all six stay freely implementable outside at_chops; only declaring a *seventh* family is closed off
- breaking: `String get name` is declared once on `AtAlgorithm` rather than on each interface. External `implements` users must add it — including `AtKeyAgreementAlgorithm` implementers, which previously had no `name`; the two X25519 backends now report `'x25519'` from the new `KeyAgreementAlgoType` enum. Both backends of an algorithm report the same name (`MlDsa65FfiAlgo`/`MlDsa65PureDartAlgo` → `'mldsa65'`; `AesGcm256FfiAlgo`/`AesGcm256EncryptionAlgo` → `'aesgcm256'`; likewise ML-KEM-768 and X-Wing), so a downstream protocol keying on it sees one stable identifier regardless of backend
- feat: add `EncryptionAlgoType` (`aesctr`, `aesgcm256`, `rsa`), `KemAlgoType` (`mlkem768`, `xwing`) and `KeyAgreementAlgoType` (`x25519`), and a `static fromString(String name)` on `SigningAlgoType`, `EncryptionAlgoType`, `KemAlgoType`, and `KeyAgreementAlgoType` alongside the existing `HashingAlgoType.fromString`. Constants are spelled all-lowercase so that `.name` *is* the identifier an algorithm reports — there is no second, camelCase vocabulary to translate between. `fromString` is case-insensitive and throws `AtException` on an unknown name
- chore: `package:at_chops/at_chops.dart` (the web-safe barrel) now compiles to WASM (dart2wasm), enforced by a CI smoke test. FFI-backed algorithms remain in `package:at_chops/at_chops_ffi.dart`, which is not WASM-compatible by design
- chore: drop the unused `dart_periphery` dependency
- chore: consolidate every classical primitive onto pointycastle and drop seven dependencies — `args` (never imported), `encrypt`, `crypton`, `crypto`, `ecdsa`, `elliptic`, and the abandoned `better_cryptography` fork. AES-CTR/GCM, RSA (PKCS#1 v1.5 encryption and signatures, plus the X.509 SPKI / PKCS#8 DER codec that `crypton` used to provide), ECDSA secp256r1, Argon2id, HMAC-SHA256 and the MD5/SHA digests are now pointycastle; `cryptography` remains for Ed25519 and X25519, and `pqcrypto` for ML-DSA-65/ML-KEM-768. Stays on `pointycastle ^3.9.1` — nothing here needs pointycastle 4, and `encrypt ^5.0.3` (still a direct dependency of at_client) pins `pointycastle ^3.x`. Every wire format is unchanged — `test/golden_vectors_test.dart` pins the AES-CTR ciphertexts (including the all-zeroes legacy IV), the RSA signatures/ciphertexts and DER encodings, and the Argon2id digests that at_auth's passphrase envelopes depend on, against known-answer vectors captured from 3.x

## 3.4.1
- fix: export `Argon2idHashingAlgo` and `Md5HashingAlgo` from the main `at_chops.dart` barrel so callers can use all supported hashing algorithms through the public package import.

## 3.4.0
- feat: add `AtSignatureAlgorithm` — new stateless signing interface (`signBytes`/`verifyBytes`, key material passed per call); `MlDsa65PureDartAlgo` and `MlDsa65FfiAlgo` implement it directly. `message` is positional; key material is passed via required named parameters so same-typed byte arguments cannot be silently transposed
- breaking: `MlDsa65PureDartAlgo.generateKeyPair`/`signBytes`/`verifyBytes` are instance methods (were static in 3.3.0) and `MlDsa65FfiAlgo.signBytes`/`verifyBytes` key material moves to named parameters — 3.3.0 call sites get a compile error instead of silently binding bytes to the wrong slots
- feat: add `at_chops_ffi.dart` barrel and `AtPqc` namespace; `AtPqc.mlDsa65`/`AtPqc.xWing` auto-select FFI or pure-Dart at first access for encapsulate/decapsulate/sign/verify and key generation
- feat: add `AesGcm256FfiAlgo` — AES-256-GCM authenticated encryption (AEAD) backed by OpenSSL 3 via FFI (`EVP_aes_256_gcm`), fully interoperable with the pure-Dart `AesGcm256EncryptionAlgo`. Exported from `at_chops_ffi.dart` (not the web-safe main barrel), since it carries `dart:ffi` bindings. Adds the `libCryptoSupportsAesGcm` capability probe
- feat: `AtPqc.aesGcm256(key)` auto-selects the FFI or pure-Dart AES-256-GCM backend at call time, mirroring `AtPqc.xWing`/`AtPqc.mlDsa65`. AES-GCM is the AEAD layer of the PQ-HPKE construction, so it is resolved through `AtPqc` like the other PQ backends. It is a factory method rather than a static field because the algorithm requires a key at construction time
- feat: add `RawKeyPairBytes` mixin — `publicKeyBytes`/`privateKeyBytes` on `XWingKeyPair`, `MlDsa65KeyPair`, `MlKem768KeyPair`, and `X25519KeyPair`; callers no longer need to manually `base64Decode` the `AtPublicKey`/`AtPrivateKey` strings
- breaking: remove FFI algorithm exports (`MlKem768FfiAlgo`, `X25519FfiAlgo`, `XWingFfiAlgo`, `MlDsa65FfiAlgo`, `openssl_loader`) from `at_chops.dart` — import `at_chops_ffi.dart` instead
- breaking: `AtKemAlgorithm` gains an abstract `generateKeyPair()` — external `implements` users must add it. The method is seedless at the interface (seed length/format are backend-specific); deterministic generation stays on the concrete classes' optional `seed` parameter
- deprecate: the stateful `secretKey` setter, `sign`, and `verify` on `MlDsa65PureDartAlgo` and `MlDsa65FfiAlgo` (both still implement `AtSigningAlgorithm`) — use `signBytes`/`verifyBytes`, or `AtPqc.mlDsa65` typed as `AtSignatureAlgorithm`
- deprecate: `AtSigningAlgorithm` (`@sealed`) — implement `AtSignatureAlgorithm` for new code instead
- fix: export the algorithm interfaces (`AtSignatureAlgorithm`, `AtKemAlgorithm`, etc.) from `at_chops.dart` — previously only reachable via `types.dart`
- feat: `AtChopsImpl._getVerificationAlgorithm` now resolves `SigningAlgoType.mldsa65` to `MlDsa65PureDartAlgo`

## 3.3.0
- feat: Add `pqSeal`/`pqOpen` — HPKE-style PQ encryption over X-Wing KEM with AES-256-GCM and forward-compatible versioning
- feat: Add direct algorithm and key-generation APIs for `at_chops`
- feat: Deprecate `AtChops`, `AtChopsImpl`, `AtChopsKeys`, and related result/input metadata compatibility types in favour of direct algorithm usage
- feat: Add static key-generation helpers on key classes

## 3.2.1
- docs: update README to document PQC algorithms (ML-DSA-65, ML-KEM-768, X-Wing, X25519), FFI vs pure-Dart backends, and usage examples

## 3.2.0
- feat: Add `XWingPureDartAlgo` — the X-Wing hybrid post-quantum/traditional
  KEM (draft-connolly-cfrg-xwing-kem-10; X25519 + ML-KEM-768), with
  `AtXWingKeyPair` and `AtChopsUtil.generateXWingKeyPair()`; verified
  against the draft's test vectors byte-exact
- feat: Add `XWingFfiAlgo` — the OpenSSL/FFI X-Wing backend, composing
  `MlKem768FfiAlgo` and `X25519FfiAlgo` (X-Wing has no native OpenSSL
  primitive). Fully interoperable with `XWingPureDartAlgo` and verified against
  the draft vector. Supporting additions: `MlKem768FfiAlgo.generateKeyPairFromSeed`
  (FIPS 203 `d || z` seed import) and `X25519FfiAlgo.publicKeyFromPrivate`
- feat: `MlKem768PureDartAlgo.encapsulate` accepts optional deterministic
  randomness (FIPS 203 `m`) for test-vector verification
- feat: Add `AesGcm256EncryptionAlgo` — AES-256-GCM authenticated encryption
  (pure-Dart via `cryptography`); output `ciphertext || tag`, explicit
  12-byte nonce, tamper detection via `AtDecryptionException`
- refactor: consolidate the key classes (`AtPublicKey`, `AtPrivateKey`,
  `SymmetricKey`, `AsymmetricKeyPair`) under a single sealed hierarchy in
  `src/key/keys.dart`, replacing `at_key_pair.dart` / `at_private_key.dart` /
  `at_public_key.dart`. The public class names and constructors are unchanged
  and remain exported from `package:at_chops/at_chops.dart`; only direct
  `src/`-path imports of the removed files are affected.
- feat: Add ML-DSA-65 digital signature algorithm (pure-Dart via `pqcrypto` package and OpenSSL FFI backends)
- feat: Add `AtMlDsa65KeyPair` key type (public key: 1952 bytes, secret key: 4032 bytes)
- feat: Add `AtChopsUtil.generateMlDsa65KeyPair()` utility method
- feat: Add OpenSSL capability probe (`libCryptoSupportsMlDsa65`) to skip ML-DSA-65 FFI tests on OpenSSL < 3.3
- fix: Refactor `libCryptoSupportsMlKem768` to share implementation with new `libCryptoSupportsMlDsa65`
- fix: Emit warning to stderr when `AT_CHOPS_LIBCRYPTO_PATH` is set but fails to open
- chore: Rename example files to follow `lower_case_with_underscores` convention
- fix: correct `AtMlDsa65KeyPair` import path from removed `at_key_pair.dart` to `keys.dart`
- fix(test): FFI tests now call `fail()` instead of `skip()` when `libcrypto` is unavailable or does not support the required algorithm

## 3.1.0
- feat: Add X25519 key agreement algorithm (pure-Dart via `cryptography` package and OpenSSL FFI backends)
- feat: Add ML-KEM-768 key encapsulation algorithm (pure-Dart via `pqcrypto` package and OpenSSL FFI backends)
- feat: Introduce `AtKemAlgorithm` and `AtKeyAgreementAlgorithm` interfaces for post-quantum cryptography
- feat: Add `AtX25519KeyPair` and `AtMlKem768KeyPair` key types with `fromBytes` constructors
- feat: Add OpenSSL capability probe (`libCryptoSupportsMlKem768`) to skip ML-KEM-768 FFI tests on OpenSSL < 3.3
- build[deps]: Add `pqcrypto` and `cryptography` dependencies for PQC algorithm support

## 3.0.0
- feat: Faster AES encryption/decryption using better_crypto
- refactor: bring all keys into the same import underneath a unified sealed class
## 2.2.0
- feat: Implement "argon2id" hashing algorithm to generate hash from a given passphrase.
- feat: Add generics to "AtEncryptionAlgorithm" and "AtHashingAlgorithm" to support multiple data types in their
  implementations.
- build[deps]: Upgraded the following packages:
  - at_commons to v5.0.2
  - args to v2.6.0
  - lints to v5.0.0
  - test to v1.25.8
  - collection to v1.19.1
## 2.1.0
- feat: New library available called `at_chops_types` which provides type definitions for using custom algorithms with
  at_chops
## 2.0.1
- fix: throw Exception when input IV is null for decryption(with Symmetric Encryption)
- build[deps]: Upgraded the following packages:
    - at_commons to v5.0.0
    - at_utils to v3.0.19
## 2.0.0
- [Breaking Change] fix: removed deprecated methods and members
- [Breaking Change] feat: Introduced interface for ASymmetricEncryptionAlgorithm and modified DefaultEncryptionAlgorithm
- build[deps]:
    - changed minimum dart version in pubspec from 2.15.1 to 3.0.0
    - upgraded pointycastle to 3.7.4
## 1.0.7
- build[deps]: Upgraded the following packages:
    - at_commons to v4.0.0
    - at_utils to v3.0.16
    - crypton to v2.2.1
    - encrypt to v5.0.3
    - crypto to v3.0.3
    - ecdsa to v0.1.0
    - elliptic to v0.3.10
    - pointycastle to v3.7.3
    - dart_periphery to v0.9.5
## 1.0.6
- fix: Pass optional parameter "keyName" to encryptBytes and decryptBytes
- fix: Export "at_key_pair.dart" file
## 1.0.5
- feat: Changes for at_auth package
- chore: fixed analyzer issues
## 1.0.4
- feat: Deprecated symmetric key pair in AtChopsKeys and introduced selfEncryptionKey and apkamSymmetricKey
- chore: Upgrade at_commons to 3.0.53 and at_util to 3.0.15
- fix: Removed at_onboarding_cli dependency in pubspec
## 1.0.3
- chore: Changed the Dart SDK version to 2.15.1 from 2.18.3 to support dependent packages
## 1.0.2
- feat: changes for pkam using private key from secure element.
## 1.0.1
- feat: Added implementation for different signing algorithms.
## 1.0.0
- Initial version.
