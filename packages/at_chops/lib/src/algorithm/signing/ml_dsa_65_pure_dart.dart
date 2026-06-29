import 'dart:typed_data';

import 'package:at_chops/src/algorithm/at_algorithm.dart';
import 'package:pqcrypto/pqcrypto.dart';

/// ML-DSA-65 (FIPS 204) pure-Dart signing.
///
/// Entry points: [generateKeyPair], then the static [signBytes] / [verifyBytes].
final class MlDsa65PureDartAlgo extends AtSigningAlgorithm {
  /// Returns raw `(publicKey: 1952 bytes, secretKey: 4032 bytes)`.
  static Future<({Uint8List publicKey, Uint8List secretKey})>
      generateKeyPair() async {
    final (Uint8List pk, Uint8List sk) =
        MlDsa.generateKeyPair(DilithiumParams.mlDsa65);
    return (publicKey: pk, secretKey: sk);
  }

  /// Signs [message] with [secretKey]; returns the 3309-byte signature.
  static Future<Uint8List> signBytes(
          Uint8List message, Uint8List secretKey) async =>
      MlDsa.sign(secretKey, message, DilithiumParams.mlDsa65);

  /// Returns `true` if [signature] was produced over [message] with the
  /// private key corresponding to [publicKey].
  static Future<bool> verifyBytes(
          Uint8List message, Uint8List signature, Uint8List publicKey) async =>
      MlDsa.verify(publicKey, message, signature, DilithiumParams.mlDsa65);
}
