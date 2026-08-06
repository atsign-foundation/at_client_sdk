import 'dart:async';
import 'dart:typed_data';

import 'package:at_chops/src/algorithm/at_algorithm.dart';
// ignore: implementation_imports
import 'package:pqcrypto/src/algos/kyber/kem.dart' show KyberLevel;
import 'package:pqcrypto/pqcrypto.dart';

/// ML-KEM-1024 (FIPS 203) KEM backed by pure-Dart (`package:pqcrypto`).
///
/// The **no-hybrid** option, and the reason it exists is citation rather than
/// strength. Used on its own it is the only public-key encryption path here
/// whose specification chain contains no draft at all — FIPS 203 for the KEM,
/// SP 800-227 §4.3 for feeding its shared secret to a key-derivation function,
/// SP 800-56C for the derivation itself. Every hybrid alternative, this
/// package's included, has its *combiner* specified only in an IETF draft.
///
/// It is also CNSA 2.0's mandated parameter set. Per NSA's own IETF profile
/// documents, CNSA 2.0 requires ML-KEM-1024 and treats hybrids as
/// non-compliant, so an atSign serving that market wants this and not the
/// hybrid.
///
/// What it gives up is the classical hedge. The hybrid covers exactly one
/// scenario — ML-KEM falling to *classical* cryptanalysis before a
/// cryptographically relevant quantum computer exists. It contributes nothing
/// against a quantum adversary, because its traditional half is Shor-broken;
/// stating that the other way round is a common error and a reviewer will
/// correct it.
///
/// Sizes (FIPS 203 Table 3): 1568-byte encapsulation key, 3168-byte
/// decapsulation key, 1568-byte ciphertext, 32-byte shared secret. The
/// ciphertext is 448 bytes larger than the hybrid's, which is the cost that
/// shows up per sealed record.
///
/// Stateless — safe to share the single [instance].
final class MlKem1024PureDartAlgo implements AtKemAlgorithm {
  static const MlKem1024PureDartAlgo instance = MlKem1024PureDartAlgo._();

  const MlKem1024PureDartAlgo._();

  // pqcrypto's KyberKem at k=4, eta1=2, eta2=2, du=11, dv=5 — FIPS 203's
  // ML-KEM-1024 parameter set.
  static final KyberKem _kem = KyberKem(KyberLevel.kem1024);

  static const int publicKeyLength = 1568;
  static const int secretKeyLength = 3168;
  static const int ciphertextLength = 1568;
  static const int sharedSecretLength = 32;

  /// The seed length FIPS 203 and HPKE both use for a persisted private key:
  /// the 64-byte `d || z`.
  ///
  /// Two independent IETF documents settle this in favour of the seed rather
  /// than the expanded key — `draft-ietf-hpke-pq` gives `Nsk = 64` for the
  /// ML-KEM code points, and `draft-ietf-jose-pqc-kem` requires a JWK's `priv`
  /// to be "the 64-octet ML-KEM seed d || z".
  static const int seedLength = 64;

  /// Generate a fresh ML-KEM-1024 key pair.
  ///
  /// [seed] is the 64-byte `d || z`; supplying it makes generation
  /// deterministic, which is what the published vectors need and what a
  /// key file storing the seed rather than the expanded key relies on.
  @override
  Future<({Uint8List publicKey, Uint8List secretKey})> generateKeyPair(
      [Uint8List? seed]) async {
    final (Uint8List pk, Uint8List sk) = _kem.generateKeyPair(seed);
    return (publicKey: pk, secretKey: sk);
  }

  /// Encapsulate a fresh shared secret against [publicKey].
  ///
  /// [seed] is the 32-byte FIPS 203 randomness `m`, for derandomised
  /// encapsulation. Supply it only to reproduce a published vector — a real
  /// seal must draw fresh randomness, or two seals share a shared secret.
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
