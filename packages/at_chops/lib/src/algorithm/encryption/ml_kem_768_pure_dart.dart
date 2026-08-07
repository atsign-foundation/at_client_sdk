import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:at_chops/src/algorithm/at_algorithm.dart';
// ignore: implementation_imports
import 'package:pqcrypto/src/algos/kyber/kem.dart' show KyberLevel;
import 'package:pqcrypto/pqcrypto.dart';

/// ML-KEM-768 (FIPS 203) KEM backed by pure-Dart (`package:pqcrypto`).
///
/// Stateless — safe to share a single instance. This is the only backend
/// whose secret keys are real, serializable byte arrays — the FFI variant
/// ([MlKem768FfiAlgo]) stores OpenSSL `EVP_PKEY*` pointers and returns
/// opaque process-lifetime handles instead.
final class MlKem768PureDartAlgo implements AtKemAlgorithm {
  static const MlKem768PureDartAlgo instance = MlKem768PureDartAlgo._();

  const MlKem768PureDartAlgo._();

  // pqcrypto's KyberKem object — ML-KEM-768 / kyber768 security level.
  static final KyberKem _kem = KyberKem(KyberLevel.kem768);

  /// FIPS 203's `d || z`, the form both `draft-ietf-hpke-pq` and
  /// `draft-ietf-jose-pqc-kem` persist a private key in.
  static const int seedLength = 64;

  @override
  Uint8List newSeed() {
    final Random random = Random.secure();
    return Uint8List.fromList(
        List<int>.generate(seedLength, (_) => random.nextInt(256)));
  }

  /// The pair [seed] produces — the only correct way to recover this key from
  /// storage, since [generateKeyPair]'s 2400-byte `secretKey` does not yield
  /// the public half back.
  @override
  Future<({Uint8List publicKey, Uint8List secretKey})> keyPairFromSeed(
      Uint8List seed) {
    if (seed.length != seedLength) {
      throw ArgumentError.value(seed.length, 'seed',
          'ML-KEM-768 seed must be $seedLength bytes (d || z)');
    }
    return generateKeyPair(seed);
  }

  /// Generate a fresh ML-KEM-768 key pair.
  ///
  /// Returns raw `(publicKey: 1184 bytes, secretKey: 2400 bytes)`. Optionally
  /// accepts a 64-byte [seed] (d||z) for deterministic generation — testing
  /// only.
  @override
  Future<({Uint8List publicKey, Uint8List secretKey})> generateKeyPair(
      [Uint8List? seed]) async {
    final (Uint8List pk, Uint8List sk) = _kem.generateKeyPair(seed);
    return (publicKey: pk, secretKey: sk);
  }

  /// Encapsulate a fresh shared secret against [publicKey].
  ///
  /// Optionally accepts the 32-byte randomness [seed] (FIPS 203 `m`) for
  /// deterministic encapsulation — testing only.
  @override
  Future<({Uint8List ciphertext, Uint8List sharedSecret})> encapsulate(
      Uint8List publicKey,
      [Uint8List? seed]) async {
    final (Uint8List ct, Uint8List ss) = _kem.encapsulate(publicKey, seed);
    return (ciphertext: ct, sharedSecret: ss);
  }

  @override
  Future<Uint8List> decapsulate(
      Uint8List secretKey, Uint8List ciphertext) async {
    return _kem.decapsulate(secretKey, ciphertext);
  }
}
