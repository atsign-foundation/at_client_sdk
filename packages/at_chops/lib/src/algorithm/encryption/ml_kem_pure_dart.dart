import 'dart:async';
import 'dart:typed_data';

import 'package:at_chops/src/algorithm/at_algorithm.dart';
import 'package:at_chops/src/algorithm/spec/output_length.dart';
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
abstract base class MlKemPureDart with KemSeedMixin implements AtKemAlgorithm {
  final KyberLevel _level;

  const MlKemPureDart(this._level);

  // One KyberKem per level, shared across instances (both are stateless).
  static final Map<KyberLevel, KyberKem> _kems = {};
  KyberKem get _kem => _kems.putIfAbsent(_level, () => KyberKem(_level));

  /// FIPS 203's `d || z` — 64 bytes at every ML-KEM level.
  @override
  int get kemSeedLength => 64;

  // ── Level sizes ─────────────────────────────────────────────────────────
  //
  // Every length check below is expressed against these rather than against
  // a level's own spec class, because this implementation serves more than
  // one parameter set. A constant naming a single level here would validate
  // ML-KEM-1024 against ML-KEM-768's sizes and reject every well-formed key.

  /// How this level names itself in diagnostics, e.g. `ML-KEM-768`.
  String get algorithmName;

  /// Raw public (encapsulation) key size at this level.
  int get publicKeyBytes;

  /// Raw secret (expanded decapsulation) key size at this level.
  ///
  /// A pure-Dart-only figure: the FFI backend's "secret key" is an opaque
  /// process-lifetime handle rather than key material, which is why the
  /// shared spec classes deliberately omit a secret-key size.
  int get secretKeyBytes;

  /// Ciphertext size at this level.
  int get ciphertextBytes;

  /// Shared secret size — 32 bytes at every ML-KEM level.
  int get sharedSecretBytes => 32;

  /// Throws [ArgumentError] unless [value] is exactly [expected] bytes.
  ///
  /// `pqcrypto` validates internally too; this is the check that does not
  /// depend on a private API reached through an `implementation_imports`
  /// ignore, so it stays correct if a future `pqcrypto` release moves it.
  void _requireLength(
      Uint8List value, int expected, String argName, String label) {
    if (value.length != expected) {
      throw ArgumentError.value(value.length, argName,
          '$algorithmName $label must be $expected bytes');
    }
  }

  @override
  Future<({Uint8List publicKey, Uint8List secretKey})> keyPairFromValidatedSeed(
          Uint8List seed) =>
      generateKeyPair(seed);

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
    checkOutputLength(pk.length, publicKeyBytes,
        operation: '$algorithmName generateKeyPair', label: 'public key');
    checkOutputLength(sk.length, secretKeyBytes,
        operation: '$algorithmName generateKeyPair', label: 'secret key');
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
    return _encapsulate(publicKey, null);
  }

  /// Derandomised encapsulation: [m] is the 32-byte FIPS 203 randomness.
  ///
  /// Exists to reproduce published vectors; production callers use
  /// [encapsulate].
  @visibleForTesting
  Future<({Uint8List ciphertext, Uint8List sharedSecret})> encapsulateDerand(
      Uint8List publicKey, Uint8List m) async {
    return _encapsulate(publicKey, m);
  }

  /// The one encapsulation path, so the length checks cannot apply to only
  /// one of the two entry points above.
  ({Uint8List ciphertext, Uint8List sharedSecret}) _encapsulate(
      Uint8List publicKey, Uint8List? m) {
    _requireLength(publicKey, publicKeyBytes, 'publicKey', 'public key');
    final (Uint8List ct, Uint8List ss) = _kem.encapsulate(publicKey, m);
    checkOutputLength(ct.length, ciphertextBytes,
        operation: '$algorithmName encapsulate', label: 'ciphertext');
    checkOutputLength(ss.length, sharedSecretBytes,
        operation: '$algorithmName encapsulate', label: 'shared secret');
    return (ciphertext: ct, sharedSecret: ss);
  }

  @override
  Future<Uint8List> decapsulate(
      Uint8List secretKey, Uint8List ciphertext) async {
    // Secret key first: a caller passing a wrong-length key should hear about
    // that key, not about the ciphertext it was going to open.
    _requireLength(secretKey, secretKeyBytes, 'secretKey', 'secret key');
    _requireLength(ciphertext, ciphertextBytes, 'ciphertext', 'ciphertext');
    final Uint8List ss = _kem.decapsulate(secretKey, ciphertext);
    checkOutputLength(ss.length, sharedSecretBytes,
        operation: '$algorithmName decapsulate', label: 'shared secret');
    return ss;
  }
}
