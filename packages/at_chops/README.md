Package for Cryptographic and Hashing Operations (CHOPS) such as encryption, decryption,
data signing, key agreement, and hashing that can be leveraged by client applications using the Atsign Protocol.

## Features

- Asymmetric encryption/decryption using RSA-2048 and RSA-4096
- Symmetric encryption/decryption using AES-128, AES-192, and AES-256 (CTR and GCM modes)
- Digest signing and verification for PKAM authentication (RSA, ECC secp256r1, Ed25519)
- Data signing and verification for public data in the Atsign Protocol
- Post-quantum digital signatures: ML-DSA-65 (FIPS 204) — pure-Dart and OpenSSL FFI backends
- Post-quantum key encapsulation: ML-KEM-768 (FIPS 203) — pure-Dart and OpenSSL FFI backends; ML-KEM-1024 (FIPS 203, IANA HPKE KEM id 0x0042) — pure-Dart
- Hybrid PQ/classical KEM: X-Wing (X25519 + ML-KEM-768, IANA HPKE KEM id 0x647A)
- Elliptic-curve key agreement: X25519 — pure-Dart and OpenSSL FFI backends
- Seed-based KEM key persistence (`newSeed` / `keyPairFromSeed`) that means the same thing on every backend
- Serializable key-pair generation helpers for RSA, X25519, ML-KEM-768, ML-DSA-65, and X-Wing
- Hashing: SHA-256, SHA-512, MD5, Argon2id
- HKDF key derivation

## Getting started

Developers should have a basic understanding of asymmetric and symmetric encryption, as well as key encapsulation mechanisms (KEMs) for the PQC APIs.

Use the algorithm classes directly. Generate or load key material first, then
pass it to the relevant encryption, signing, key agreement, KEM, or hashing
class.

## Usage

Examples assume `package:at_chops/at_chops.dart` is imported. Snippets using
`utf8` or `Uint8List` also require `dart:convert` or `dart:typed_data`.

### Serializable key generation

Use these helpers when the key material needs to fit the SDK's string-backed key
types (`AtPublicKey`, `AtPrivateKey`, and `SymmetricKey`). Byte-oriented key
pairs are base64-encoded by the wrapper classes.

```dart
final aes128 = AESKey.generate(16);
final aes192 = AESKey.generate(24);
final aes256 = AESKey.generate(32);

final rsa2048 = RsaKeyPair.generate();
final rsa4096 = RsaKeyPair.generate(keySize: 4096);

final x25519 = await X25519KeyPair.generate();
final mlKem768 = await MlKem768KeyPair.generate();
final mlDsa65 = await MlDsa65KeyPair.generate();
final xWing = await XWingKeyPair.generate();
```

### RSA encryption

```dart
final keyPair = RsaKeyPair.generate();
final rsa = RsaEncryptionAlgo.fromKeyPair(keyPair);
final message = Uint8List.fromList(utf8.encode('Hello World'));

final encrypted = rsa.encrypt(message);
final decrypted = rsa.decrypt(encrypted);
```

### AES encryption

```dart
final aesKey = AESKey.generate(32);
final iv = InitialisationVector.random(16);
final aes = AESEncryptionAlgo(aesKey);
final message = Uint8List.fromList(utf8.encode('Hello World'));

final encrypted = await aes.encrypt(message, iv: iv);
final decrypted = await aes.decrypt(encrypted, iv: iv);
```

### Signing and verification

```dart
final keyPair = RsaKeyPair.generate();
final signing = RsaSigningAlgo(keyPair, HashingAlgoType.sha256);
final message = Uint8List.fromList(utf8.encode('data to sign'));

final signature = signing.sign(message);
final valid = signing.verify(message, signature);
```

### ML-DSA-65 (post-quantum signing, pure-Dart)

```dart
final mlDsa65 = MlDsa65PureDartAlgo();
final kp = await mlDsa65.generateKeyPair();
// kp.publicKey — 1952 bytes; kp.secretKey — 4032 bytes

final signature = await mlDsa65.signBytes(message, secretKey: kp.secretKey);
final valid =
    await mlDsa65.verifyBytes(message, signature: signature, publicKey: kp.publicKey);
```

### ML-KEM-768 (post-quantum KEM, pure-Dart)

```dart
final kem = MlKem768PureDartAlgo.instance;
final kp = await kem.generateKeyPair();
// kp.publicKey — 1184 bytes
// kp.secretKey — 2400 bytes, the expanded decapsulation key. NOT a seed:
// see "Persisting a KEM key" below before storing it.

// Sender
final (ciphertext: ct, sharedSecret: ss1) = await kem.encapsulate(kp.publicKey);

// Receiver
final ss2 = await kem.decapsulate(kp.secretKey, ct);
// ss1 == ss2
```

### ML-KEM-1024 (post-quantum KEM, pure-Dart)

The no-hybrid option, for callers whose specification chain has to contain no
draft — FIPS 203 for the KEM itself — and the parameter set CNSA 2.0 mandates.
Same interface, larger sizes; its ciphertext is 448 bytes bigger than X-Wing's,
which is the cost that shows up per sealed record.

```dart
final kem = MlKem1024PureDartAlgo.instance;
final kp = await kem.generateKeyPair();
// kp.publicKey — 1568 bytes; kp.secretKey — 3168 bytes (expanded, not a seed)

final (ciphertext: ct, sharedSecret: ss1) = await kem.encapsulate(kp.publicKey);
final ss2 = await kem.decapsulate(kp.secretKey, ct);
// ss1 == ss2
```

### X-Wing (hybrid PQ/classical KEM)

```dart
final xwing = XWingPureDartAlgo.instance;
final kp = await xwing.generateKeyPair();
// kp.publicKey — 1216 bytes; kp.secretKey — 32 bytes, which for THIS backend
// happens to be the seed. Don't generalise that — see below.

// Sender
final (ciphertext: ct, sharedSecret: ss1) = await xwing.encapsulate(kp.publicKey);

// Receiver
final ss2 = await xwing.decapsulate(kp.secretKey, ct);
// ss1 == ss2
```

### Persisting a KEM key

`generateKeyPair`'s `secretKey` is what `decapsulate` takes, and it does **not**
mean the same thing on every backend: X-Wing's *is* its 32-byte seed, ML-KEM's is
the expanded decapsulation key that no seeded call reproduces, and the FFI
backends' is an opaque handle that does not outlive the process. So code written
against X-Wing persists recoverable bytes by accident, and the identical code
persists unrecoverable ones for ML-KEM — with no compile error, and no failure
until a restart.

Store the **seed** and re-derive. That is correct on every backend, and it is the
only form in which a caller can hold a key for a KEM it does not name in source.

```dart
// Any backend — the two calls mean the same thing on all of them.
final AtKemAlgorithm kem = XWingPureDartAlgo.instance;

// Minting: keep the seed, not the secret key.
final seed = kem.newSeed();
final kp = await kem.keyPairFromSeed(seed);

// Recovering, after a restart — from the stored seed:
final recovered = await kem.keyPairFromSeed(seed);
// recovered.publicKey == kp.publicKey
```

Seed lengths are backend-specific (32 bytes for X-Wing, 64 for ML-KEM's
`d || z`) and deliberately absent from the interface: `newSeed` makes a valid
one and `keyPairFromSeed` rejects an invalid one. Concrete classes expose
`seedLength` for callers that do name a backend. Store the algorithm alongside
the seed — 32 and 64 bytes are both valid for *some* backend, so the bytes alone
cannot say which.

### AtPqc (auto-resolved PQ backends)

`AtPqc` is the recommended entry point for PQ crypto — it auto-resolves the
OpenSSL FFI backend when `libcrypto` supports it, falling back to pure-Dart
otherwise, so callers don't need to pick a backend by hand. Import
`package:at_chops/at_chops_ffi.dart` to access it.

```dart
import 'package:at_chops/at_chops_ffi.dart';

// Signing — AtPqc.mlDsa65 is typed as AtSignatureAlgorithm
final kp = await MlDsa65KeyPair.generate();
final signature =
    await AtPqc.mlDsa65.signBytes(message, secretKey: kp.privateKeyBytes);
final valid = await AtPqc.mlDsa65.verifyBytes(message,
    signature: signature, publicKey: kp.publicKeyBytes);

// KEM — AtPqc.xWing is typed as AtKemAlgorithm
final xwKp = await XWingKeyPair.generate();
final (ciphertext: ct, sharedSecret: ss1) = await AtPqc.xWing.encapsulate(xwKp.publicKeyBytes);
final ss2 = await AtPqc.xWing.decapsulate(xwKp.privateKeyBytes, ct);
// ss1 == ss2
```

### X25519 (Diffie–Hellman, pure-Dart)

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

AES-256-GCM also has an OpenSSL FFI backend (`AesGcm256FfiAlgo`) alongside its pure-Dart counterpart (`AesGcm256EncryptionAlgo`); the two are fully interoperable. `AtPqc.aesGcm256(key)` auto-selects FFI or pure-Dart when AAD is not needed. If you need AAD (e.g. for PQ-HPKE), construct `AesGcm256FfiAlgo.fromLib(lib, key)` or `AesGcm256EncryptionAlgo(key)` directly — both expose `encrypt`/`decrypt` with `{List<int> aad}`.

FFI backends are exported from `package:at_chops/at_chops_ffi.dart`, not the
main `at_chops.dart` barrel, so pure-Dart-only consumers aren't forced to
carry FFI bindings. Use [AtPqc](#atpqc-auto-resolved-pq-backends) instead of
picking an FFI/pure-Dart backend directly when possible.

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
