import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:at_chops/src/algorithm/at_iv.dart';
import 'package:at_chops/src/key/at_key_pair.dart';
import 'package:at_chops/src/key/at_private_key.dart';
import 'package:at_chops/src/key/at_public_key.dart';
import 'package:at_chops/src/model/hash_params.dart';

/// Interface for encrypting and decrypting data. Check [DefaultEncryptionAlgo] for sample implementation.
abstract class AtEncryptionAlgorithm<T, V> {
  /// Encrypts the passed bytes. Bytes are passed as [Uint8List]. Encode String data type to [Uint8List] using [utf8.encode].
  V encrypt(T plainData);

  /// Decrypts the passed encrypted bytes.
  V decrypt(T encryptedData);
}

/// Interface for symmetric encryption algorithms. Check [AESEncryptionAlgo] for sample implementation.
abstract class SymmetricEncryptionAlgorithm<T, V>
    extends AtEncryptionAlgorithm<T, V> {
  @override
  V encrypt(T plainData, {InitialisationVector iv});

  @override
  V decrypt(T encryptedData, {InitialisationVector iv});
}

/// Interface for asymmetric encryption algorithms. Check [DefaultEncryptionAlgo] for sample implementation.
abstract class ASymmetricEncryptionAlgorithm
    extends AtEncryptionAlgorithm<Uint8List, Uint8List> {
  AtPublicKey? atPublicKey;
  AtPrivateKey? atPrivateKey;

  /// Encrypt [plainData] with [atPublicKey.publicKey]
  @override
  Uint8List encrypt(Uint8List plainData);

  /// Decrypt [encryptedData] with [atPrivateKey.privateKey]
  @override
  Uint8List decrypt(Uint8List encryptedData);
}

/// Interface for data signing. Data is signed using private key from a key pair
/// Signed data signature is verified with public key of the key pair.
abstract class AtSigningAlgorithm {
  /// Signs the data using private key of asymmetric key pair
  FutureOr<Uint8List> sign(Uint8List data);

  /// Verifies the data signature using public key of asymmetric key pair or the passed [publicKey]
  FutureOr<bool> verify(Uint8List signedData, Uint8List signature,
      {String? publicKey});
}

/// Interface for hashing data. Refer [DefaultHash] for sample implementation.
abstract class AtHashingAlgorithm<K, V> {
  /// Hashes the passed data
  FutureOr<V> hash(K data, {covariant HashParams? hashParams});
}
