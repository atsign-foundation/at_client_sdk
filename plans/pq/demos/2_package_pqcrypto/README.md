# 2_package_pqcrypto — Hybrid X25519 + ML-KEM-768 (pure Dart)

Demonstrates a hybrid post-quantum key exchange using **X25519** and **ML-KEM-768**, implemented entirely in pure Dart with no native libraries or FFI.

## How it works

1. **X25519** — classical ECDH key exchange between Alice and Bob
2. **ML-KEM-768** — post-quantum KEM via the [`pqcrypto`](https://pub.dev/packages/pqcrypto) package (`PqcKem.kyber768`)
3. **HKDF-SHA256** — combines both shared secrets (`mlkem_ss || x25519_ss`) into a 32-byte hybrid key
4. **AES-256-GCM** — encrypts a test message with the hybrid key
5. **SHA-256** — produces a session fingerprint over the combined secrets
6. **AES-256-CTR** — encrypts a second message in stream-cipher mode (no authentication tag)

## Difference from 1_liboqs_ffi

`1_liboqs_ffi` calls into `liboqs.dylib` via FFI for ML-KEM-768. `2_package_pqcrypto` replaces that with the pure-Dart `pqcrypto` package — no dynamic library, no platform-specific setup required.

## Run

```sh
dart run
```
