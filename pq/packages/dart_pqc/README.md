# dart_pqc

ML-KEM-768, X25519, and Ed25519 for Dart. Each primitive ships with two tiers:

| Tier | Requires |
|---|---|
| FFI (OpenSSL 3) | `libcrypto` on the native platform |
| Pure Dart | nothing — works on all platforms |

Use the `resolve*` functions to get the fastest available implementation automatically.

---

## Installation

```yaml
dependencies:
  ffi: ^2.1.0
  cryptography: ^2.7.0
  pqcrypto:
    git:
      url: git@github.com:JeremyTubongbanua/pqcrypto.git
      ref: main
  dart_pqc:
    path: path/to/dart_pqc
```

---

## ML-KEM-768

A post-quantum Key Encapsulation Mechanism (FIPS 203). The sender encapsulates a fresh shared secret against the recipient's public key; the recipient decapsulates to recover the same secret.

```
Alice  generateKeyPair()     → (publicKey, secretKey)
Bob    encapsulate(publicKey) → (ciphertext, sharedSecret)
Alice  decapsulate(secretKey, ciphertext) → sharedSecret
```

Key sizes: public key 1184 B · secret key 2400 B · ciphertext 1088 B · shared secret 32 B

### Auto-resolved

```dart
import 'package:dart_pqc/dart_pqc.dart';

final MlKem768Algorithm kem = resolveMlKem768();
// prints to stderr: [dart_pqc] ML-KEM-768 → MlKem768Ffi  (or MlKem768PureDart)

final PqcKeyPair kp = await kem.generateKeyPair();
final EncapsulationResult enc = await kem.encapsulate(kp.publicKey);
final Uint8List ss = await kem.decapsulate(kp.secretKey, enc.ciphertext);
// enc.sharedSecret == ss
```

### Pure Dart

```dart
final MlKem768Algorithm kem = MlKem768PureDart.instance;
```

Backed by the [JeremyTubongbanua/pqcrypto](https://github.com/JeremyTubongbanua/pqcrypto) fork with all FIPS 203 interoperability fixes applied.

Deterministic key generation (testing only):

```dart
final Uint8List seed = Uint8List(64); // 64-byte seed: d || z
final PqcKeyPair kp = await kem.generateKeyPair(seed);
```

### OpenSSL FFI

```dart
import 'dart:ffi';
import 'package:dart_pqc/dart_pqc.dart';

final DynamicLibrary lib = DynamicLibrary.open('/opt/homebrew/lib/libcrypto.dylib');
final MlKem768Ffi kem = MlKem768Ffi.fromLib(lib);

final PqcKeyPair kp = await kem.generateKeyPair();
final EncapsulationResult enc = await kem.encapsulate(kp.publicKey);
final Uint8List ss = await kem.decapsulate(kp.secretKey, enc.ciphertext);
kem.releaseKeyPair(kp); // free the native EVP_PKEY*
```

> **Note:** OpenSSL's EVP API does not expose raw ML-KEM-768 secret key bytes. `secretKey` is an 8-byte opaque handle valid only within the same process. Call `releaseKeyPair` when done.

---

## X25519

Diffie-Hellman key agreement over Curve25519. Both parties contribute a key pair; `dh()` computes the shared secret from one party's private key and the other's public key.

```
Alice  generateKeyPair() → (alicePk, aliceSk)
Bob    generateKeyPair() → (bobPk, bobSk)
Alice  dh(aliceSk, bobPk) → sharedSecret
Bob    dh(bobSk, alicePk) → sharedSecret   // same value
```

Key sizes: public key 32 B · private key 32 B · shared secret 32 B

### Auto-resolved

```dart
import 'package:dart_pqc/dart_pqc.dart';

final X25519Algorithm x25519 = resolveX25519();
// prints to stderr: [dart_pqc] X25519 → X25519Ffi  (or X25519PureDart)

final (publicKey: Uint8List alicePk, privateKey: Uint8List aliceSk) =
    await x25519.generateKeyPair();
final (publicKey: Uint8List bobPk, privateKey: Uint8List bobSk) =
    await x25519.generateKeyPair();

final Uint8List ss1 = await x25519.dh(aliceSk, bobPk);
final Uint8List ss2 = await x25519.dh(bobSk, alicePk);
// ss1 == ss2
```

### Pure Dart

```dart
final X25519PureDart x25519 = X25519PureDart.instance;
```

### OpenSSL FFI

```dart
import 'dart:ffi';
import 'package:dart_pqc/dart_pqc.dart';

final DynamicLibrary lib = DynamicLibrary.open('/opt/homebrew/lib/libcrypto.dylib');
final X25519Ffi x25519 = X25519Ffi.fromLib(lib);
```

---

## Ed25519

Edwards-curve digital signature algorithm. Sign with a private key; verify with the corresponding public key.

Key sizes: public key 32 B · private key 32 B · signature 64 B

### Auto-resolved

```dart
import 'package:dart_pqc/dart_pqc.dart';

final Ed25519Algorithm ed25519 = resolveEd25519();
// prints to stderr: [dart_pqc] Ed25519 → Ed25519Ffi  (or Ed25519PureDart)

final (publicKey: Uint8List pk, privateKey: Uint8List sk) =
    await ed25519.generateKeyPair();

final Uint8List message = Uint8List.fromList('hello'.codeUnits);
final Uint8List signature = await ed25519.sign(sk, message);

final bool valid = await ed25519.verify(pk, message, signature);
```

### Pure Dart

```dart
final Ed25519PureDart ed25519 = Ed25519PureDart.instance;
```

### OpenSSL FFI

```dart
import 'dart:ffi';
import 'package:dart_pqc/dart_pqc.dart';

final DynamicLibrary lib = DynamicLibrary.open('/opt/homebrew/lib/libcrypto.dylib');
final Ed25519Ffi ed25519 = Ed25519Ffi.fromLib(lib);
```

---

## OpenSSL library resolution

Each `resolve*` call prints one line to `stderr` identifying the chosen implementation:

```
[dart_pqc] ML-KEM-768 → MlKem768Ffi
[dart_pqc] X25519    → X25519Ffi
[dart_pqc] Ed25519   → Ed25519Ffi
```

The library is probed once at process startup. The `resolve*` functions try the following in order:

1. Path in the `DART_PQC_LIBCRYPTO_PATH` environment variable.
2. `/opt/homebrew/lib/libcrypto.dylib` (macOS, Apple Silicon Homebrew)
3. `/usr/local/lib/libcrypto.dylib` (macOS, Intel Homebrew)
4. `libcrypto.so.3` (Linux, OpenSSL 3)
5. `libcrypto.so` (Linux, generic)

Falls back to pure Dart silently if none load. OpenSSL 3.x is required — OpenSSL 1.x does not include ML-KEM-768.

```sh
DART_PQC_LIBCRYPTO_PATH=/custom/path/libcrypto.so dart run example/main.dart
```

---

## Running the tests

```sh
cd pq/packages/dart_pqc
dart pub get
dart test
```
