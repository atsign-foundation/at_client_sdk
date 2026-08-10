Package for Cryptographic and Hashing Operations (CHOPS) such as encryption, decryption,
data signing, key agreement, and hashing that can be leveraged by client applications using the Atsign Protocol.

## Features

- Asymmetric encryption/decryption using RSA-2048 and RSA-4096
- Symmetric encryption/decryption using AES-128, AES-192, and AES-256 (CTR and GCM modes)
- Digest signing and verification for PKAM authentication (RSA, ECC secp256r1, Ed25519)
- Data signing and verification for public data in the Atsign Protocol
- Post-quantum digital signatures: ML-DSA-65 (FIPS 204) — pure-Dart and OpenSSL FFI backends
- Post-quantum key encapsulation: ML-KEM-768 (FIPS 203) — pure-Dart and OpenSSL FFI backends
- Hybrid PQ/classical KEM: X-Wing (X25519 + ML-KEM-768, draft-connolly-cfrg-xwing-kem-10)
- Elliptic-curve key agreement: X25519 — pure-Dart and OpenSSL FFI backends
- Key generation on every algorithm: `generateKey()` on the symmetric ones, `generateKeyPair()` on the asymmetric ones (both return raw bytes)
- Hashing: SHA-256, SHA-512, MD5, Argon2id
- HKDF key derivation
- One sealed supertype, `AtAlgorithm`, over every algorithm family — hold any algorithm in one variable, read its `name`, or switch over the families exhaustively

## Getting started

Developers should have a basic understanding of asymmetric and symmetric encryption, as well as key encapsulation mechanisms (KEMs) for the PQC APIs.

Use the algorithm classes directly. Generate or load key material first, then
pass it to the relevant encryption, signing, key agreement, KEM, or hashing
class.

### Algorithm interfaces

Every algorithm implements one of six family interfaces, and all six implement
the sealed `AtAlgorithm`. Use `AtAlgorithm` when you need one type that holds
any algorithm — its only member is `name`, the stable identifier a downstream
protocol keys on (`'aesgcm256'`, `'mldsa65'`, `'x25519'`, …), which is always
the corresponding enum constant's `name`.

| Family interface | Enum | Implementations |
| --- | --- | --- |
| `SymmetricEncryptionAlgorithm`  | `EncryptionAlgoType`   | `AesCtrEncryptionAlgo`, `AesGcm256EncryptionAlgo`, `AesGcm256FfiAlgo` |
| `ASymmetricEncryptionAlgorithm` | `EncryptionAlgoType`   | `RsaEncryptionAlgo` |
| `AtSignatureAlgorithm`          | `SigningAlgoType`      | `RsaSigningAlgo`, `EccSigningAlgo`, `Ed25519SigningAlgo`, `MlDsa65PureDartAlgo`, `MlDsa65FfiAlgo` |
| `AtKemAlgorithm`                | `KemAlgoType`          | `MlKem768PureDartAlgo`, `MlKem768FfiAlgo`, `XWingPureDartAlgo`, `XWingFfiAlgo` |
| `AtHashingAlgorithm<K, V>`      | `HashingAlgoType`      | `SHA256HashingAlgo`, `SHA512HashingAlgo`, `Md5HashingAlgo`, `Argon2idHashingAlgo` |
| `AtKeyAgreementAlgorithm`       | `KeyAgreementAlgoType` | `X25519PureDartAlgo`, `X25519FfiAlgo` |

Because `AtAlgorithm` is sealed, a switch over the families needs no default
arm — adding a seventh family to at_chops becomes a compile error you have to
handle rather than a silent fallthrough:

```dart
String familyOf(AtAlgorithm algo) => switch (algo) {
      AtSignatureAlgorithm() => 'signature',
      SymmetricEncryptionAlgorithm() => 'symmetric',
      ASymmetricEncryptionAlgorithm() => 'asymmetric',
      AtKemAlgorithm() => 'kem',
      AtHashingAlgorithm() => 'hashing',
      AtKeyAgreementAlgorithm() => 'keyAgreement',
    };
```

Sealing is not transitive: the six family interfaces themselves stay open, so
you can still implement `AtSignatureAlgorithm` (or any other) in your own
package. Import `package:at_chops/types.dart` to do so.

## Usage

Examples assume `package:at_chops/at_chops.dart` is imported. Snippets using
`utf8` or `Uint8List` also require `dart:convert` or `dart:typed_data`.

### Key generation

Every algorithm generates its own key material, sized to that algorithm — there
is no shared key-generation helper. Symmetric algorithms expose `generateKey()`
on `SymmetricEncryptionAlgorithm`; signing, KEM, and key-agreement algorithms
expose `generateKeyPair()`, which returns raw `Uint8List` public/secret keys
(see the per-algorithm sections below).

```dart
final gcmKey = AesGcm256EncryptionAlgo().generateKey(); // always 32 bytes
final ctrKey = AesCtrEncryptionAlgo(24).generateKey();  // 24 bytes, as configured

final (:publicKey, :secretKey) = await RsaSigningAlgo().generateKeyPair();
```

### RSA encryption

`RsaEncryptionAlgo` is stateless: the public key is passed to `encrypt` and the
private key to `decrypt`, as the raw DER bytes `RsaSigningAlgo.generateKeyPair()`
produces.

```dart
final rsa = RsaEncryptionAlgo();
final (:publicKey, :secretKey) = await RsaSigningAlgo().generateKeyPair();
final message = Uint8List.fromList(utf8.encode('Hello World'));

final encrypted = rsa.encrypt(message, publicKey);
final decrypted = rsa.decrypt(encrypted, secretKey);
```

### AES encryption

`AesCtrEncryptionAlgo` is AES-CTR: unauthenticated, key length fixed at
construction, key bytes passed per call. Prefer `AesGcm256EncryptionAlgo` for
new data — it authenticates the ciphertext.

`iv` is required on every symmetric `encrypt`/`decrypt`: none of the algorithms
generate one for you or hand a generated one back, and reusing a (key, iv) pair
is a security bug — so the caller owns it. To read data written back when IVs
weren't being set, pass `InitialisationVector.legacy()`.

```dart
final aes = AesCtrEncryptionAlgo(32); // 16 / 24 / 32 bytes
final key = aes.generateKey();
final iv = InitialisationVector.random(16);
final message = Uint8List.fromList(utf8.encode('Hello World'));

final encrypted = await aes.encrypt(message, key, iv: iv);
final decrypted = await aes.decrypt(encrypted, key, iv: iv);
```

### Signing and verification

The classical signing algorithms (`RsaSigningAlgo`, `EccSigningAlgo`,
`Ed25519SigningAlgo`) implement the same stateless `AtSignatureAlgorithm`
interface as the post-quantum backends — `generateKeyPair()`, `signBytes()`,
and `verifyBytes()`, with all key material passed per call as raw bytes.

`verifyBytes()` returns normally iff the signature is good. A wrong key, a
tampered message or a forged signature throws `AtSigningVerificationException`
rather than returning `false` — a failed verification is an error, and a
boolean is too easy to drop on the floor.

```dart
final signing = RsaSigningAlgo(); // SHA-256, 2048-bit by default
final kp = await signing.generateKeyPair();
final message = Uint8List.fromList(utf8.encode('data to sign'));

final signature = await signing.signBytes(message, secretKey: kp.secretKey);
await signing.verifyBytes(message,
    signature: signature, publicKey: kp.publicKey); // throws if invalid
```

### ML-DSA-65 (post-quantum signing, pure-Dart)

```dart
final mlDsa65 = MlDsa65PureDartAlgo();
final kp = await mlDsa65.generateKeyPair();
// kp.publicKey — 1952 bytes; kp.secretKey — 4032 bytes

final signature = await mlDsa65.signBytes(message, secretKey: kp.secretKey);
await mlDsa65.verifyBytes(message,
    signature: signature, publicKey: kp.publicKey); // throws if invalid
```

### ML-KEM-768 (post-quantum KEM, pure-Dart)

```dart
final kem = MlKem768PureDartAlgo.instance;
final kp = await kem.generateKeyPair();
// kp.publicKey — 1184 bytes; kp.secretKey — 2400 bytes

// Sender
final (ciphertext: ct, sharedSecret: ss1) = await kem.encapsulate(kp.publicKey);

// Receiver
final ss2 = await kem.decapsulate(kp.secretKey, ct);
// ss1 == ss2
```

### X-Wing (hybrid PQ/classical KEM)

```dart
final xwing = XWingPureDartAlgo.instance;
final kp = await xwing.generateKeyPair();
// kp.publicKey — 1216 bytes; kp.secretKey — 32 bytes (seed)

// Sender
final (ciphertext: ct, sharedSecret: ss1) = await xwing.encapsulate(kp.publicKey);

// Receiver
final ss2 = await xwing.decapsulate(kp.secretKey, ct);
// ss1 == ss2
```

### AtPqc (auto-resolved PQ backends)

`AtPqc` is the recommended entry point for PQ crypto — it auto-resolves the
OpenSSL FFI backend when `libcrypto` supports it, falling back to pure-Dart
otherwise, so callers don't need to pick a backend by hand. Import
`package:at_chops/at_chops_ffi.dart` to access it.

```dart
import 'package:at_chops/at_chops_ffi.dart';

// Signing — AtPqc.mlDsa65 is typed as AtSignatureAlgorithm
final kp = await AtPqc.mlDsa65.generateKeyPair();
final signature =
    await AtPqc.mlDsa65.signBytes(message, secretKey: kp.secretKey);
await AtPqc.mlDsa65.verifyBytes(message,
    signature: signature, publicKey: kp.publicKey); // throws if invalid

// KEM — AtPqc.xWing is typed as AtKemAlgorithm
final xwKp = await AtPqc.xWing.generateKeyPair();
final (ciphertext: ct, sharedSecret: ss1) = await AtPqc.xWing.encapsulate(xwKp.publicKey);
final ss2 = await AtPqc.xWing.decapsulate(xwKp.secretKey, ct);
// ss1 == ss2
```

### X25519 (Diffie–Hellman, pure-Dart)

`X25519PureDartAlgo` and `X25519FfiAlgo` implement `AtKeyAgreementAlgorithm`
and both report `name == 'x25519'`.

```dart
final x25519 = X25519PureDartAlgo.instance;
final kpA = await x25519.generateKeyPair();
final kpB = await x25519.generateKeyPair();

final ssA = await x25519.dh(kpA.privateKey, kpB.publicKey);
final ssB = await x25519.dh(kpB.privateKey, kpA.publicKey);
// ssA == ssB
```

### Hashing

```dart
final hash = SHA512HashingAlgo().hash('some-data'.codeUnits);
```

## FFI backends

ML-DSA-65, ML-KEM-768, and X25519 each have an OpenSSL FFI backend (`MlDsa65FfiAlgo`, `MlKem768FfiAlgo`, `X25519FfiAlgo`) that requires `libcrypto` to be installed. The pure-Dart backends (`*PureDartAlgo`) work on all platforms without native dependencies.

X-Wing (`XWingFfiAlgo`) composes the FFI backends for maximum performance when `libcrypto` is available.

AES-256-GCM also has an OpenSSL FFI backend (`AesGcm256FfiAlgo`) alongside its pure-Dart counterpart (`AesGcm256EncryptionAlgo`); the two are fully interoperable. `AtPqc.aesGcm256` auto-selects FFI or pure-Dart when AAD is not needed. If you need AAD (e.g. for PQ-HPKE), construct `AesGcm256FfiAlgo.fromLib(lib)` or `AesGcm256EncryptionAlgo()` directly — both expose `encrypt`/`decrypt` with `{List<int> aad}`.

FFI backends are exported from `package:at_chops/at_chops_ffi.dart`, not the
main `at_chops.dart` barrel, so pure-Dart-only consumers aren't forced to
carry FFI bindings. Use [AtPqc](#atpqc-auto-resolved-pq-backends) instead of
picking an FFI/pure-Dart backend directly when possible.

## Web / WASM

The main barrel `package:at_chops/at_chops.dart` is pure-Dart and compiles to
WebAssembly (dart2wasm); a CI smoke test (`tool/wasm_compat_check.dart`) enforces
this. `package:at_chops/at_chops_ffi.dart` carries `dart:ffi`/`dart:io` bindings
and is **not** WASM/web compatible by design — web consumers must import only
`at_chops.dart`.

## Running Tests

Some tests require `libcrypto.so` to be installed. Running `dart test` without it will fail those tests.

To run all tests EXCEPT the FFI tests:

```bash
dart test --exclude-tags ffi
```

To run ONLY the FFI tests:

```bash
dart test --tags ffi
```
