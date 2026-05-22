# 3_openssl_ffi_and_pqcrypto_package_comparison

Blackbox interoperability test for ML-KEM-768: checks whether the [`pqcrypto`](https://pub.dev/packages/pqcrypto) package's implementation is compatible with OpenSSL 3.6's ML-KEM-768.

## What it tests

Four tests, two sanity checks and two cross-implementation checks:

| Test | Keygen | Encaps | Decaps | Purpose |
|------|--------|--------|--------|---------|
| A | OpenSSL | OpenSSL | OpenSSL | Sanity: OpenSSL is internally consistent |
| B | pqcrypto | pqcrypto | pqcrypto | Sanity: pqcrypto is internally consistent |
| **C** | **OpenSSL** | **pqcrypto** | **OpenSSL** | **Interop: can OpenSSL decapsulate a pqcrypto ciphertext?** |
| **D** | **pqcrypto** | **OpenSSL** | **pqcrypto** | **Interop: can pqcrypto decapsulate an OpenSSL ciphertext?** |

## Result

```
[PASS] OpenSSL encaps/decaps shared secrets match
[PASS] pqcrypto encaps/decaps shared secrets match
[FAIL] OpenSSL keygen + pqcrypto encaps + OpenSSL decaps: shared secrets match
[FAIL] pqcrypto keygen + OpenSSL encaps + pqcrypto decaps: shared secrets match
```

Both libraries are internally self-consistent but the shared secrets do not match in the cross-implementation tests. The two implementations are not interoperable.

## Prerequisites

### Dart SDK ≥ 3.11

```sh
dart --version
```

### OpenSSL 3.6 via Homebrew

```sh
brew install openssl@3.6
```

The demo loads `/opt/homebrew/opt/openssl@3.6/lib/libcrypto.dylib` directly — no build step required.

## Run

```sh
dart pub get
dart run bin/main.dart
```

The program exits with code `1` if any interoperability test fails, or `0` if all pass.

## How it works

**OpenSSL side** — Dart FFI binds directly to `libcrypto.dylib` using the EVP high-level API:

- `EVP_PKEY_CTX_new_from_name` + `EVP_PKEY_keygen` — generate an ML-KEM-768 keypair
- `EVP_PKEY_get1_encoded_public_key` — extract the 1184-byte raw public key
- `EVP_PKEY_fromdata` — import a raw public key for encapsulation
- `EVP_PKEY_encapsulate_init` + `EVP_PKEY_encapsulate` — encapsulate
- `EVP_PKEY_decapsulate_init` + `EVP_PKEY_decapsulate` — decapsulate

**pqcrypto side** — uses `PqcKem.kyber768` from the `pqcrypto` package (pure Dart, no native libs).

The cross-tests pass public key bytes directly between the two implementations. Since ML-KEM-768 public keys are 1184 raw bytes, they are directly comparable across implementations with no format conversion needed.

## Dependencies

| Package | Purpose |
|---------|---------|
| [`pqcrypto`](https://pub.dev/packages/pqcrypto) | Pure-Dart ML-KEM-768 |
| [`ffi`](https://pub.dev/packages/ffi) | `calloc` allocator for native memory |
| [`path`](https://pub.dev/packages/path) | Path resolution |
| OpenSSL 3.6 (`libcrypto.dylib`) | Reference ML-KEM-768 implementation |
