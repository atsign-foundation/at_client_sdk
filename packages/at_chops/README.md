Package for Cryptographic and Hashing Operations (CHOPS) such as encryption, decryption,
data signing and hashing that can  be leveraged by client applications using the at protocol.

## Features

- Asymmetric public/private key encryption/decryption using RSA
- Symmetric key encryption/decryption using AES
- Digest signing and verification for PKAM authentication
- Data signing and verification for public data in the at protocol
- Hashing operations 

## Getting started

- Developer should have a basic understanding on how asymmetric and symmetric encryption works.
- Developers can use their own key pairs/keys to use this package or create new key pairs/keys using [AtChopsUtil]

## Usage

```dart
final atChopsKeys = AtChopsKeys.create(atEncryptionKeyPair, null);
final atChops = AtChopsImpl(atChopsKeys);
final data = 'Hello World';
final encryptedString = atChops.encryptString(data, EncryptionKeyType.rsa_2048);
final decryptedString = atChops.decryptString(encryptedString, EncryptionKeyType.rsa_2048);
```

## Running Tests

We have at_chops tests that require `libcrypto.so` installed for them to pass. Therefore, running `dart test` will not pass on all systems.

To run all tests EXCEPT the FFI tests:

```bash
dart test --exclude-tags ffi
```

To run ONLY the FFI tests:

```bash
dart test --tags ffi
```
