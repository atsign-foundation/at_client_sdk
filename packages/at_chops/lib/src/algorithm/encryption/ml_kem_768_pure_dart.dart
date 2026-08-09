import 'package:at_chops/src/algorithm/encryption/ml_kem_pure_dart.dart';
// ignore: implementation_imports
import 'package:pqcrypto/src/algos/kyber/kem.dart' show KyberLevel;

/// ML-KEM-768 (FIPS 203) KEM backed by pure-Dart (`package:pqcrypto`).
///
/// Key pairs are raw `(publicKey: 1184 bytes, secretKey: 2400 bytes)`.
/// Stateless — safe to share a single instance. This is the only backend
/// whose secret keys are real, serializable byte arrays — the FFI variant
/// ([MlKem768FfiAlgo]) stores OpenSSL `EVP_PKEY*` pointers and returns
/// opaque process-lifetime handles instead.
final class MlKem768PureDartAlgo extends MlKemPureDart {
  static const MlKem768PureDartAlgo instance = MlKem768PureDartAlgo._();

  const MlKem768PureDartAlgo._() : super(KyberLevel.kem768);

  /// FIPS 203's `d || z`, the form both `draft-ietf-hpke-pq` and
  /// `draft-ietf-jose-pqc-kem` persist a private key in.
  static const int seedLength = 64;

  @override
  String get kemSeedDescription => 'an ML-KEM-768 seed (d || z)';
}
