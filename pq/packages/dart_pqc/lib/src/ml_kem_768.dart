/// Pure-Dart ML-KEM-768 implementation backed by the JeremyTubongbanua/pqcrypto
/// fork (FIPS 203-compliant with all interoperability fixes applied).

import 'dart:typed_data';

import 'package:pqcrypto/pqcrypto.dart';
import 'package:pqcrypto/src/algos/kyber/kem.dart' show KyberLevel;

import 'dart_pqc_base.dart';

/// ML-KEM-768 KEM using the pure-Dart pqcrypto package.
///
/// This is the fallback path used when the FFI-accelerated OpenSSL shared
/// object is unavailable (e.g. on Web or when no native library is bundled).
final class MlKem768PureDart implements KemAlgorithm {
  /// Singleton instance — stateless, safe to share.
  static const MlKem768PureDart instance = MlKem768PureDart._();

  const MlKem768PureDart._();

  @override
  String get name => 'ML-KEM-768';

  /// The underlying pqcrypto KEM object (ML-KEM-768 / kyber768 security level).
  static final KyberKem _kem = KyberKem(KyberLevel.kem768);

  @override
  Future<PqcKeyPair> generateKeyPair([Uint8List? seed]) async {
    final (Uint8List pk, Uint8List sk) = _kem.generateKeyPair(seed);
    return PqcKeyPair(publicKey: pk, secretKey: sk);
  }

  @override
  Future<EncapsulationResult> encapsulate(Uint8List publicKey) async {
    final (Uint8List ct, Uint8List ss) = _kem.encapsulate(publicKey);
    return EncapsulationResult(ciphertext: ct, sharedSecret: ss);
  }

  @override
  Future<Uint8List> decapsulate(Uint8List secretKey, Uint8List ciphertext) async {
    return _kem.decapsulate(secretKey, ciphertext);
  }
}
