## 3.4.2
- test: **ML-DSA-65 conformance against NIST's ACVP vectors** (FIPS 204). Until
  now `ml_dsa_65_algo_test.dart` asserted key and signature lengths and that a
  signature round-trips, which two wrong implementations agreeing with each
  other would also satisfy — and ML-DSA-65 authenticates every PQ enrollment.
  70 published vectors now run: 25 keyGen (the seed reproduces the published
  keypair byte-exactly), 15 deterministic sigGen (the signature bytes
  themselves, since with the hedging value fixed at zero the signature is a
  pure function of key, message and context), 15 hedged sigGen, and 15 sigVer
  carrying **both arms** — NIST's own negative cases, each naming what was
  corrupted. Filtered to ML-DSA-65 and the external/pure interface, which is
  all this package implements; nothing was dropped for size, and the exclusions
  are listed in the fixture's `_provenance` object.
- test: three further tests pin that at_chops signs and verifies with an
  **empty context string**, which is what RFC 9964 requires of the ML-DSA JOSE
  algorithms. The context is the one FIPS 204 parameter at_chops fixes rather
  than passes through, so getting it wrong would produce signatures no RFC 9964
  verifier accepts while every round-trip test here stayed green.
- test: **X25519 conformance against RFC 7748** — section 6.1's Diffie-Hellman
  vector, including deriving each published public key from its private key
  against the base point, and section 5.2's raw scalar-multiplication vectors,
  which exercise clamping and the ladder independently of any key-pair
  convention. The existing tests only checked that two generated key pairs
  agreed with each other.
- fix: `ArgonHashParams.salt` — Argon2id derivation takes a real salt.
  `Argon2idHashingAlgo.hash` passed the password's own UTF-16 code units as the
  Argon2id nonce, so derivation was deterministic in the passphrase and the
  salt carried no entropy of its own. It still falls back to that when `salt`
  is null, because key files already written derived their keys that way and
  would otherwise become undecryptable — but the fallback is now documented as
  a compatibility path rather than a design.
- feat: `ArgonHashParams.owaspMinimum` carries OWASP's current Argon2id floor
  (m=19456 KiB, t=2, p=1). The defaults on `ArgonHashParams` stay at
  m=10000/t=2/p=2, which is below that floor, because they are pinned by every
  file already written rather than chosen.
- test: X-Wing now conforms to the **IETF HPKE working group's** published
  vectors for IANA HPKE KEM id `0x647A`, not only to
  `draft-connolly-cfrg-xwing-kem-10`'s Appendix C. Both published rows are
  checked across all three operations — key generation from the seed,
  derandomised encapsulation, and decapsulation — in both the pure-Dart and
  OpenSSL FFI backends. The FFI backend gets its own rows because it carries a
  second copy of the combiner and the SHAKE-256 seed expansion, and the
  existing interop tests would pass with both backends wrong in the same way.
  This matters because the draft is an Independent Submission CFRG never
  adopted, it expires 2026-09-03, and its own Appendix C is marked TODO by its
  authors, so it was the weakest citation available for the construction.
  No production code changed.
- docs: X-Wing is cited by its IANA HPKE KEM id `0x647A` rather than by the
  expiring draft, with the naming caveat recorded: the registry row still reads
  *X-Wing*, and the rename to `MLKEM768-X25519` requested by
  `draft-ietf-hpke-pq` has not been effected. Also records the **Bouncy Castle
  1.81 floor** for anyone implementing this in Java — 1.78 to 1.80 feed the
  combiner label first rather than last and derive a different shared secret,
  which surfaces as an opaque AEAD failure rather than a key error.
- feat: `PkamMlDsa65SigningAlgo` — synchronous ML-DSA-65 PKAM signing and
  verification, and `AtChopsImpl`'s pkam dispatch now honours
  `signingAlgoType: mldsa65`. Until now the pkam branch signed RSA regardless
  of the requested algorithm, so a client could never produce a genuine
  ML-DSA PKAM signature; the key material rides the existing String-typed
  `AtPkamKeyPair` slot as base64 of the raw keys. The mldsa65 *verification*
  branch also switches to the synchronous class — it previously returned
  `MlDsa65PureDartAlgo`, whose `Future<bool>` verify was stored unawaited in
  the bool-typed result.
- fix: `pqOpen` honours its documented contract when the KEM rejects the input.
  A wrong-length recipient secret key or KEM ciphertext reaches `decapsulate`,
  which raises an `ArgumentError` — that sat outside the guard, so a caller
  told to catch `PqOpenException` got an uncaught error on nothing worse than
  a malformed envelope. It now arrives as
  `PqOpenException(PqOpenFailure.malformedEnvelope, ...)`.

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
