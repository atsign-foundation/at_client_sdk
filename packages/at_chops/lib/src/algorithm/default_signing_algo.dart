import 'dart:typed_data';

import 'package:at_chops/src/algorithm/algo_type.dart';
import 'package:at_chops/src/algorithm/at_algorithm.dart';
import 'package:at_chops/src/key/impl/at_encryption_key_pair.dart';
import 'package:at_commons/at_commons.dart';
import 'package:crypton/crypton.dart';

/// Data signing and verification using atsign encryption keypair
/// Allowed algorithms are listed in [SigningAlgoType] and [HashingAlgoType]
class DefaultSigningAlgo implements AtSigningAlgorithm {
  final AtEncryptionKeyPair? _encryptionKeyPair;
  final HashingAlgoType _hashingAlgoType;

  DefaultSigningAlgo(this._encryptionKeyPair, this._hashingAlgoType);

  @override
  Uint8List sign(Uint8List data) {
    if (_encryptionKeyPair == null) {
      throw AtSigningException(
          'encryption key pair not set for default signing algo');
    }
    final rsaPrivateKey =
        RSAPrivateKey.fromString(_encryptionKeyPair!.atPrivateKey.privateKey);
    switch (_hashingAlgoType) {
      case HashingAlgoType.sha256:
        return rsaPrivateKey.createSHA256Signature(data);
      case HashingAlgoType.sha512:
        return rsaPrivateKey.createSHA512Signature(data);
      default:
        throw AtSigningException(
            'Hashing algo $_hashingAlgoType is invalid/not supported');
    }
  }

  @override
  bool verify(Uint8List signedData, Uint8List signature, {String? publicKey}) {
    RSAPublicKey? rsaPublicKey;
    if (publicKey != null) {
      rsaPublicKey = RSAPublicKey.fromString(publicKey);
    } else if (_encryptionKeyPair != null) {
      rsaPublicKey =
          RSAPublicKey.fromString(_encryptionKeyPair!.atPublicKey.publicKey);
    } else {
      throw AtSigningVerificationException(
          'Encryption key pair or public key not set for default signing algo');
    }
    switch (_hashingAlgoType) {
      case HashingAlgoType.sha256:
        return rsaPublicKey.verifySHA256Signature(signedData, signature);
      case HashingAlgoType.sha512:
        return rsaPublicKey.verifySHA512Signature(signedData, signature);
      default:
        throw AtSigningVerificationException(
            'Invalid hashing algo $_hashingAlgoType provided');
    }
  }
}
