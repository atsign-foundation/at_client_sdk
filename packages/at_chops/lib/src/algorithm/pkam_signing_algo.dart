import 'dart:typed_data';

import 'package:at_chops/src/algorithm/algo_type.dart';
import 'package:at_chops/src/algorithm/at_algorithm.dart';
import 'package:at_chops/src/key/impl/at_pkam_key_pair.dart';
import 'package:at_commons/at_commons.dart';
import 'package:crypton/crypton.dart';

/// Data signing and verification for Public Key Authentication Mechanism - Pkam
class PkamSigningAlgo implements AtSigningAlgorithm {
  final AtPkamKeyPair? _pkamKeyPair;
  final HashingAlgoType _hashingAlgoType;
  PkamSigningAlgo(this._pkamKeyPair, this._hashingAlgoType);

  @override
  Uint8List sign(Uint8List data) {
    if (_pkamKeyPair == null) {
      throw AtSigningException('pkam key pair is null. cannot sign data');
    }
    final rsaPrivateKey =
        RSAPrivateKey.fromString(_pkamKeyPair!.atPrivateKey.privateKey);
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
    RSAPublicKey rsaPublicKey;
    if (publicKey != null) {
      rsaPublicKey = RSAPublicKey.fromString(publicKey);
    } else if (_pkamKeyPair != null) {
      rsaPublicKey =
          RSAPublicKey.fromString(_pkamKeyPair!.atPublicKey.publicKey);
    } else {
      throw AtSigningVerificationException(
          'Pkam key pair or public key not set for pkam verification');
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
