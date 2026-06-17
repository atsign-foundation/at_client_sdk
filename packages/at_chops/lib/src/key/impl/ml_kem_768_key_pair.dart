import 'dart:convert';
import 'dart:typed_data';

import 'package:at_chops/src/key/keys.dart';

import '../../algorithm/encryption/ml_kem_768_pure_dart_algo.dart';

/// ML-KEM-768 (FIPS 203) key pair used for post-quantum key encapsulation.
///
/// Public keys are 1184 raw bytes; secret keys are 2400 raw bytes (pure-Dart
/// format). Both are encoded as base64 strings to fit the existing
/// [AsymmetricKeyPair] String contract. Only pure-Dart-format secret keys are
/// serializable — the OpenSSL FFI backend returns process-lifetime opaque
/// handles, so persisted ML-KEM secret keys must always be used with the
/// pure-Dart algorithm.
class MlKem768KeyPair extends AsymmetricKeyPair {
  MlKem768KeyPair.create(super.publicKey, super.privateKey) : super.create();

  /// Generates an ML-KEM-768 key pair for post-quantum key encapsulation.
  ///
  /// Backed by the pure-Dart ML-KEM-768 implementation (via `package:pqcrypto`).
  /// Raw 1184-byte public key and 2400-byte secret key are base64-encoded.
  /// Persisted ML-KEM keys must always be used with the pure-Dart algorithm
  /// — the FFI backend returns opaque process-lifetime handles instead of
  /// real bytes.
  static Future<MlKem768KeyPair> generate() async {
    final (publicKey: Uint8List pub, secretKey: Uint8List sk) =
        await MlKem768PureDartAlgo.instance.generateKeyPair();
    return MlKem768KeyPair.create(base64Encode(pub), base64Encode(sk));
  }
}
