import 'dart:async';
import 'dart:typed_data';

import 'package:at_chops/src/algo_type.dart';
import 'package:at_chops/src/at_algorithm.dart';
import 'package:at_commons/at_commons.dart';
import 'package:cryptography/cryptography.dart';

/// Ed25519 (RFC 8032) digital signatures.
///
/// Implements the stateless [AtSignatureAlgorithm] contract — all key
/// material is passed per call as raw bytes:
/// - `secretKey`: the 32-byte Ed25519 seed
/// - `publicKey`: the 32-byte Ed25519 public key
/// - signatures are 64 bytes
class Ed25519SigningAlgo implements AtSignatureAlgorithm {
  final _algorithm = Ed25519();
  @override
  String get name => SigningAlgoType.ed25519.name;
  Ed25519SigningAlgo();

  /// Generate a fresh Ed25519 key pair.
  ///
  /// Returns `(publicKey: 32 bytes, secretKey: 32-byte seed)`.
  @override
  Future<({Uint8List publicKey, Uint8List secretKey})> generateKeyPair() async {
    final keyPair = await _algorithm.newKeyPair();
    final seed = await keyPair.extractPrivateKeyBytes();
    final publicKey = await keyPair.extractPublicKey();
    return (
      publicKey: Uint8List.fromList(publicKey.bytes),
      secretKey: Uint8List.fromList(seed),
    );
  }

  /// Sign [message] with the 32-byte [secretKey] seed; returns 64 bytes.
  @override
  Future<Uint8List> signBytes(Uint8List message,
      {required Uint8List secretKey}) async {
    final keyPair = await _algorithm.newKeyPairFromSeed(secretKey);
    final signature = await _algorithm.sign(message, keyPair: keyPair);
    return Uint8List.fromList(signature.bytes);
  }

  /// Verify [signature] over [message] against the 32-byte [publicKey].
  ///
  /// Throws [AtSigningVerificationException] if the signature does not verify.
  @override
  Future<void> verifyBytes(Uint8List message,
      {required Uint8List signature, required Uint8List publicKey}) async {
    final verified = await _algorithm.verify(
      message,
      signature: Signature(
        signature,
        publicKey: SimplePublicKey(publicKey, type: KeyPairType.ed25519),
      ),
    );
    if (!verified) {
      throw AtSigningVerificationException(
          '$name signature verification failed');
    }
  }
}
