import 'dart:async';
import 'dart:typed_data';

import 'package:at_chops/src/algorithm/at_algorithm.dart';
import 'package:meta/meta.dart' show visibleForTesting;
// ignore: implementation_imports
import 'package:pqcrypto/src/algos/kyber/kem.dart' show KyberLevel;
import 'package:pqcrypto/pqcrypto.dart';

/// ML-KEM (FIPS 203) backed by pure-Dart (`package:pqcrypto`), parameterised
/// by level.
///
/// Package-internal: the exported surface is the level-pinned leaf classes
/// (`MlKem768PureDartAlgo`, `MlKem1024PureDartAlgo`), whose names say which
/// parameter set a caller gets. The two levels are the same algorithm at
/// different sizes, and as separate copies they had already begun to drift;
/// this base holds the one implementation.
abstract base class MlKemPureDart
    with KemSeedMixin
    implements AtKemAlgorithm {
  final KyberLevel _level;

  const MlKemPureDart(this._level);

  // One KyberKem per level, shared across instances (both are stateless).
  static final Map<KyberLevel, KyberKem> _kems = {};
  KyberKem get _kem => _kems.putIfAbsent(_level, () => KyberKem(_level));

  /// FIPS 203's `d || z` — 64 bytes at every ML-KEM level.
  @override
  int get kemSeedLength => 64;

  @override
  Future<({Uint8List publicKey, Uint8List secretKey})>
      keyPairFromValidatedSeed(Uint8List seed) => generateKeyPair(seed);

  /// Generate a fresh key pair, raw public and secret key bytes.
  ///
  /// The `secretKey` is the expanded decapsulation key — what [decapsulate]
  /// takes, not what a caller should persist; recover stored keys through
  /// [keyPairFromSeed]. [seed] is the 64-byte `d || z`; supplying it makes
  /// generation deterministic, which is what the published vectors need and
  /// what a key file storing the seed rather than the expanded key relies on.
  @override
  Future<({Uint8List publicKey, Uint8List secretKey})> generateKeyPair(
      [Uint8List? seed]) async {
    final (Uint8List pk, Uint8List sk) = _kem.generateKeyPair(seed);
    return (publicKey: pk, secretKey: sk);
  }

  /// Encapsulate a fresh shared secret against [publicKey].
  ///
  /// Always draws fresh randomness — there is no derandomised variant in the
  /// public API, because two seals sharing randomness share a shared secret.
  /// Vector tests reproduce published ciphertexts via [encapsulateDerand].
  @override
  Future<({Uint8List ciphertext, Uint8List sharedSecret})> encapsulate(
      Uint8List publicKey) async {
    final (Uint8List ct, Uint8List ss) = _kem.encapsulate(publicKey, null);
    return (ciphertext: ct, sharedSecret: ss);
  }

  /// Derandomised encapsulation: [m] is the 32-byte FIPS 203 randomness.
  ///
  /// Exists to reproduce published vectors; production callers use
  /// [encapsulate].
  @visibleForTesting
  Future<({Uint8List ciphertext, Uint8List sharedSecret})> encapsulateDerand(
      Uint8List publicKey, Uint8List m) async {
    final (Uint8List ct, Uint8List ss) = _kem.encapsulate(publicKey, m);
    return (ciphertext: ct, sharedSecret: ss);
  }

  @override
  Future<Uint8List> decapsulate(
      Uint8List secretKey, Uint8List ciphertext) async {
    return _kem.decapsulate(secretKey, ciphertext);
  }
}
