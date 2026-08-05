import 'dart:convert';
import 'dart:typed_data';

import 'package:at_chops/src/algo_type.dart';
import 'package:at_chops/src/at_algorithm.dart';
import 'package:crypton/crypton.dart';

/// RSA asymmetric encryption/decryption.
///
/// Stateless: the public key is passed to [encrypt] and the private key to
/// [decrypt], as raw DER bytes — exactly what `RsaSigningAlgo.generateKeyPair()`
/// returns. If you hold an `AtPublicKey`/`AtPrivateKey` (base64-encoded DER),
/// pass `base64Decode(atPublicKey.publicKey)`.
class RsaEncryptionAlgo implements ASymmetricEncryptionAlgorithm {
  RsaEncryptionAlgo();

  /// Key-size agnostic: the modulus length comes from the key passed per
  /// call, so there is no `rsa2048`/`rsa4096` split here.
  @override
  String get name => EncryptionAlgoType.rsa.name;

  @override
  Uint8List encrypt(Uint8List plainData, Uint8List publicKey) {
    final rsaPublicKey = RSAPublicKey.fromString(base64Encode(
      publicKey.toList(),
    ));
    return rsaPublicKey.encryptData(plainData);
  }

  @override
  Uint8List decrypt(Uint8List encryptedData, Uint8List privateKey) {
    final rsaPrivateKey = RSAPrivateKey.fromString(base64Encode(
      privateKey.toList(),
    ));
    return rsaPrivateKey.decryptData(encryptedData);
  }
}
