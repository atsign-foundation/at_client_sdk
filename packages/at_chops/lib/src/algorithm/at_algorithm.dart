import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:at_chops/src/algorithm/at_iv.dart';
import 'package:at_chops/src/algorithm/hashing/types.dart';
import 'package:at_chops/src/key/keys.dart';

/// Interface for encrypting and decrypting data. Check [DefaultEncryptionAlgo] for sample implementation.
abstract class AtEncryptionAlgorithm<T, V> {
  /// Encrypts the passed bytes. Bytes are passed as [Uint8List]. Encode String data type to [Uint8List] using [utf8.encode].
  FutureOr<V> encrypt(T plainData);

  /// Decrypts the passed encrypted bytes.
  FutureOr<V> decrypt(T encryptedData);
}

/// Interface for symmetric encryption algorithms. Check [AESEncryptionAlgo] for sample implementation.
abstract class SymmetricEncryptionAlgorithm<T, V>
    extends AtEncryptionAlgorithm<T, V> {
  @override
  FutureOr<V> encrypt(T plainData, {InitialisationVector iv});

  @override
  FutureOr<V> decrypt(T encryptedData, {InitialisationVector iv});
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

/// Signing algorithm — key passed per call, safe to share as a singleton.
///
/// New implementations: override [signBytes] and [verifyBytes] only.
/// Legacy implementations that override [sign]/[verify] will continue to
/// compile; those methods will be removed in v4.
abstract class AtSigningAlgorithm {
  const AtSigningAlgorithm();
  /// Signs [message] with [secretKey].
  Future<Uint8List> signBytes(Uint8List message, Uint8List secretKey) =>
      throw UnimplementedError('implement signBytes');

  /// Verifies [signature] over [message] against [publicKey].
  Future<bool> verifyBytes(
          Uint8List message, Uint8List signature, Uint8List publicKey) =>
      throw UnimplementedError('implement verifyBytes');

  /// Signs [data] using a key stored on the instance.
  @Deprecated('Implement signBytes(message, secretKey) instead.')
  FutureOr<Uint8List> sign(Uint8List data) =>
      throw UnimplementedError('implement signBytes');

  /// Verifies [signature] over [signedData].
  @Deprecated('Implement verifyBytes(message, signature, publicKey) instead.')
  FutureOr<bool> verify(Uint8List signedData, Uint8List signature,
          {String? publicKey}) =>
      throw UnimplementedError('implement verifyBytes');
}

/// Interface for hashing data. Refer [DefaultHash] for sample implementation.
abstract class AtHashingAlgorithm<K, V> {
  /// Hashes the passed data
  FutureOr<V> hash(K data, {covariant HashParams? hashParams});
}

/// Interface for a Key Encapsulation Mechanism (KEM) such as ML-KEM-768.
///
/// A KEM does not encrypt arbitrary data. It produces a shared secret that
/// both parties can derive — the sender via [encapsulate] against the
/// recipient's public key, the recipient via [decapsulate] using their
/// secret key and the ciphertext sent by the sender.
abstract class AtKemAlgorithm {
  /// Encapsulate a fresh shared secret against [publicKey].
  ///
  /// Returns the [ciphertext] to transmit to the holder of the matching
  /// secret key, together with the [sharedSecret] that both parties will
  /// derive.
  FutureOr<({Uint8List ciphertext, Uint8List sharedSecret})> encapsulate(
      Uint8List publicKey);

  /// Recover the shared secret from [ciphertext] using [secretKey].
  FutureOr<Uint8List> decapsulate(Uint8List secretKey, Uint8List ciphertext);
}

/// Interface for a Diffie–Hellman key agreement primitive such as X25519.
abstract class AtKeyAgreementAlgorithm {
  /// Compute the shared secret from [privateKey] and [peerPublicKey].
  FutureOr<Uint8List> dh(Uint8List privateKey, Uint8List peerPublicKey);
}
