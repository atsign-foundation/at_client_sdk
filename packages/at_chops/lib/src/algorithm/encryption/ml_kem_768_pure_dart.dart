import 'dart:async';
import 'dart:typed_data';

import 'package:at_chops/src/algorithm/at_algorithm.dart';
import 'package:at_chops/src/algorithm/spec/ml_kem_768_spec.dart';
import 'package:at_chops/src/algorithm/spec/output_length.dart';
// ignore: implementation_imports
import 'package:pqcrypto/src/algos/kyber/kem.dart' show KyberLevel;
import 'package:pqcrypto/pqcrypto.dart';

/// Raw secret key size for the pure-Dart backend only — deliberately not on
/// [MlKem768Sizes], since the FFI backend's "secret key" is an opaque 8-byte
/// handle rather than raw key material (see that class's dartdoc).
const int _pureDartSecretKeyBytes = 2400;

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

  /// Generate a fresh ML-KEM-768 key pair.
  ///
  /// Returns raw `(publicKey: 1184 bytes, secretKey: 2400 bytes)`. Optionally
  /// accepts a 64-byte [seed] (d||z) for deterministic generation — testing
  /// only.
  @override
  Future<({Uint8List publicKey, Uint8List secretKey})> generateKeyPair(
      [Uint8List? seed]) async {
    final (Uint8List pk, Uint8List sk) = _kem.generateKeyPair(seed);
    checkOutputLength(pk.length, MlKem768Sizes.publicKeyBytes,
        operation: 'ML-KEM-768 generateKeyPair', label: 'public key');
    checkOutputLength(sk.length, _pureDartSecretKeyBytes,
        operation: 'ML-KEM-768 generateKeyPair', label: 'secret key');
    return (publicKey: pk, secretKey: sk);
  }

  /// Encapsulate a fresh shared secret against [publicKey].
  ///
  /// Optionally accepts the 32-byte randomness [seed] (FIPS 203 `m`) for
  /// deterministic encapsulation — testing only.
  ///
  /// Validates [publicKey] length here via [MlKem768Sizes.validatePublicKey]
  /// rather than relying solely on `pqcrypto`'s private
  /// `KyberKem._validatePublicKey` — that check lives behind a
  /// `// ignore: implementation_imports` import and isn't part of
  /// `pqcrypto`'s public contract, so a future 0.3.x release could change it
  /// without warning. `pqcrypto` still validates internally too, as defense
  /// in depth.
  @override
  Future<({Uint8List ciphertext, Uint8List sharedSecret})> encapsulate(
      Uint8List publicKey,
      [Uint8List? seed]) async {
    MlKem768Sizes.validatePublicKey(publicKey);
    final (Uint8List ct, Uint8List ss) = _kem.encapsulate(publicKey, seed);
    checkOutputLength(ct.length, MlKem768Sizes.ciphertextBytes,
        operation: 'ML-KEM-768 encapsulate', label: 'ciphertext');
    checkOutputLength(ss.length, MlKem768Sizes.sharedSecretBytes,
        operation: 'ML-KEM-768 encapsulate', label: 'shared secret');
    return (ciphertext: ct, sharedSecret: ss);
  }

  /// Validates [secretKey] and [ciphertext] lengths here (via
  /// [MlKem768Sizes.validateCiphertext] for the latter) rather than relying
  /// solely on `pqcrypto`'s private `KyberKem._validateSecretKey`/
  /// `_validateCiphertext` — see the note on [encapsulate] above. `pqcrypto`
  /// still validates internally too, as defense in depth.
  @override
  Future<Uint8List> decapsulate(
      Uint8List secretKey, Uint8List ciphertext) async {
    if (secretKey.length != _pureDartSecretKeyBytes) {
      throw ArgumentError.value(secretKey.length, 'secretKey',
          'ML-KEM-768 secret key must be $_pureDartSecretKeyBytes bytes');
    }
    MlKem768Sizes.validateCiphertext(ciphertext);
    final Uint8List ss = _kem.decapsulate(secretKey, ciphertext);
    checkOutputLength(ss.length, MlKem768Sizes.sharedSecretBytes,
        operation: 'ML-KEM-768 decapsulate', label: 'shared secret');
    return ss;
  }
}
