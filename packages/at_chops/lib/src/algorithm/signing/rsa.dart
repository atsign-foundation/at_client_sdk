import 'dart:convert';
import 'dart:typed_data';

import 'package:at_chops/src/algorithm/algo_type.dart';
import 'package:at_chops/src/algorithm/at_algorithm.dart';
import 'package:at_commons/at_commons.dart';
import 'package:crypton/crypton.dart';

/// RSA (PKCS#1 v1.5) digital signatures.
///
/// The [hashingAlgoType] (SHA-256 or SHA-512) and [keySize] are algorithm
/// parameters fixed at construction; only key material is passed per call,
/// per the stateless [AtSignatureAlgorithm] contract. Key material is raw
/// DER bytes:
/// - `secretKey`: PKCS#8 DER-encoded private key
/// - `publicKey`: X.509 SubjectPublicKeyInfo DER-encoded public key
class RsaSigningAlgo implements AtSignatureAlgorithm {
  final HashingAlgoType _hashingAlgoType;
  final int _keySize;

  RsaSigningAlgo(
      {HashingAlgoType hashingAlgoType = HashingAlgoType.sha256,
      int keySize = 2048})
      : _hashingAlgoType = hashingAlgoType,
        _keySize = keySize;

  /// Generate a fresh RSA key pair of [keySize] bits.
  @override
  Future<({Uint8List publicKey, Uint8List secretKey})> generateKeyPair() async {
    final keyPair = RSAKeypair.fromRandom(keySize: _keySize);
    return (
      publicKey: base64Decode(keyPair.publicKey.toString()),
      secretKey: base64Decode(keyPair.privateKey.toString()),
    );
  }

  /// Sign [message] with the DER-encoded [secretKey].
  @override
  Future<Uint8List> signBytes(Uint8List message,
      {required Uint8List secretKey}) async {
    final rsaPrivateKey = RSAPrivateKey.fromString(base64Encode(secretKey));
    switch (_hashingAlgoType) {
      case HashingAlgoType.sha256:
        return rsaPrivateKey.createSHA256Signature(message);
      case HashingAlgoType.sha512:
        return rsaPrivateKey.createSHA512Signature(message);
      default:
        throw AtSigningException(
            'Hashing algo $_hashingAlgoType is invalid/not supported');
    }
  }

  /// Verify [signature] over [message] against the DER-encoded [publicKey].
  @override
  Future<bool> verifyBytes(Uint8List message,
      {required Uint8List signature, required Uint8List publicKey}) async {
    final rsaPublicKey = RSAPublicKey.fromString(base64Encode(publicKey));
    switch (_hashingAlgoType) {
      case HashingAlgoType.sha256:
        return rsaPublicKey.verifySHA256Signature(message, signature);
      case HashingAlgoType.sha512:
        return rsaPublicKey.verifySHA512Signature(message, signature);
      default:
        throw AtSigningVerificationException(
            'Invalid hashing algo $_hashingAlgoType provided');
    }
  }
}
