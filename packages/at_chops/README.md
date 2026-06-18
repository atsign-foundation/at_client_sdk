Package for Cryptographic and Hashing Operations (CHOPS) such as encryption, decryption,
data signing, key agreement, and hashing that can be leveraged by client applications using the atProtocol.

## Features

- Asymmetric encryption/decryption using RSA-2048 and RSA-4096
- Symmetric encryption/decryption using AES-128, AES-192, and AES-256 (CBC and GCM modes)
- Digest signing and verification for PKAM authentication (RSA, ECC secp256r1, Ed25519)
- Data signing and verification for public data in the atProtocol
- Post-quantum digital signatures: ML-DSA-65 (FIPS 204) — pure-Dart and OpenSSL FFI backends
- Post-quantum key encapsulation: ML-KEM-768 (FIPS 203) — pure-Dart and OpenSSL FFI backends
- Hybrid PQ/classical KEM: X-Wing (X25519 + ML-KEM-768, draft-connolly-cfrg-xwing-kem-10)
- Elliptic-curve key agreement: X25519 — pure-Dart and OpenSSL FFI backends
- Hashing: SHA-256, SHA-512, MD5, Argon2id
- HKDF key derivation

## Getting started

Developers should have a basic understanding of asymmetric and symmetric encryption, as well as key encapsulation mechanisms (KEMs) for the PQC APIs.

Use `AtChopsKeys` to supply key material and `AtChopsImpl` for the high-level operations. For PQC algorithms, use the algorithm classes directly (they are stateless where possible).

## Usage

### Classical encryption (RSA / AES)

```dart
final atChopsKeys = AtChopsKeys.create(atEncryptionKeyPair, null);
final atChops = AtChopsImpl(atChopsKeys);

final encrypted = await atChops.encryptString('Hello World', EncryptionKeyType.rsa2048);
final decrypted = await atChops.decryptString(encrypted.result, EncryptionKeyType.rsa2048);
```

### Signing and verification

```dart
final signingInput = AtSigningInput('data to sign')
  ..signingAlgoType = SigningAlgoType.ecc_secp256r1;
final signingResult = atChops.sign(signingInput);

final verifyInput = AtSigningVerificationInput(...)
final verifyResult = atChops.verify(verifyInput);
```

### ML-DSA-65 (post-quantum signing, pure-Dart)

```dart
final kp = await MlDsa65PureDartAlgo.generateKeyPair();
// kp.publicKey — 1952 bytes; kp.secretKey — 4032 bytes

final signature = await MlDsa65PureDartAlgo.signBytes(message, kp.secretKey);
final valid = await MlDsa65PureDartAlgo.verifyBytes(message, signature, kp.publicKey);
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
final hash = AtChops.hashWith(HashingAlgoType.sha256).hash(data);
```

## FFI backends

ML-DSA-65, ML-KEM-768, and X25519 each have an OpenSSL FFI backend (`MlDsa65FfiAlgo`, `MlKem768FfiAlgo`, `X25519FfiAlgo`) that requires `libcrypto` to be installed. The pure-Dart backends (`*PureDartAlgo`) work on all platforms without native dependencies.

X-Wing (`XWingFfiAlgo`) composes the FFI backends for maximum performance when `libcrypto` is available.

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
