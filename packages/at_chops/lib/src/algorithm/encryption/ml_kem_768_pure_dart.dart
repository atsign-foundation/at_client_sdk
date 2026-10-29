import 'dart:typed_data';

import 'package:at_chops/src/algorithm/encryption/ml_kem_pure_dart.dart';
import 'package:at_chops/src/algorithm/spec/ml_kem_768_spec.dart';
// ignore: implementation_imports
import 'package:pqcrypto/src/algos/kyber/kem.dart' show KyberLevel;

/// Raw secret key size for the pure-Dart backend only — deliberately not on
/// [MlKem768Sizes], since the FFI backend's "secret key" is an opaque 8-byte
/// handle rather than raw key material (see that class's dartdoc).
const int _pureDartSecretKeyBytes = 2400;

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

  @override
  String get algorithmName => 'ML-KEM-768';

  @override
  int get publicKeyBytes => MlKem768Sizes.publicKeyBytes;

  @override
  int get secretKeyBytes => _pureDartSecretKeyBytes;

  @override
  int get ciphertextBytes => MlKem768Sizes.ciphertextBytes;

  @override
  int get sharedSecretBytes => MlKem768Sizes.sharedSecretBytes;

  /// Encapsulate a fresh shared secret against [publicKey].
  ///
  /// The optional [seed] (the 32-byte FIPS 203 randomness `m`) is published
  /// API this class cannot remove; it exists only to reproduce vectors, and a
  /// production seal must not supply it.
  @override
  Future<({Uint8List ciphertext, Uint8List sharedSecret})> encapsulate(
          Uint8List publicKey,
          [@Deprecated('Vector tests use encapsulateDerand; a production seal '
              'draws fresh randomness')
          Uint8List? seed]) =>
      seed == null
          ? super.encapsulate(publicKey)
          // The published compat path IS the derandomised testing hook.
          // ignore: invalid_use_of_visible_for_testing_member
          : encapsulateDerand(publicKey, seed);
}
