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