import 'dart:async';
import 'dart:ffi';
import 'dart:math' show Random;
import 'dart:typed_data';

import 'package:at_chops/src/algorithm/at_algorithm.dart';
import 'package:at_chops/src/algorithm/encryption/ml_kem_768_ffi.dart';
import 'package:at_chops/src/algorithm/encryption/x25519_ffi_algo.dart';
import 'package:at_chops/src/algorithm/spec/ml_kem_768_spec.dart';
import 'package:at_chops/src/algorithm/spec/output_length.dart';
import 'package:at_chops/src/algorithm/spec/x_wing_spec.dart';
import 'package:meta/meta.dart';
import 'package:pointycastle/digests/sha3.dart';
import 'package:pointycastle/digests/shake.dart';

/// X-Wing hybrid post-quantum/traditional KEM (draft-connolly-cfrg-xwing-kem-10)
/// backed by OpenSSL 3 via Dart FFI.
///
/// X-Wing has no native OpenSSL primitive, so this composes [MlKem768FfiAlgo]
/// (ML-KEM-768) and [X25519FfiAlgo] (X25519). The seed expansion (SHAKE-256)
/// and the shared-secret combiner (SHA3-256) are pure-Dart (pointycastle) and
/// byte-identical to `XWingPureDartAlgo`, so public keys, ciphertexts and
/// shared secrets are fully interoperable between the FFI and pure-Dart
/// backends.
///
/// Unlike `XWingPureDartAlgo`, there is no derandomized encapsulation: OpenSSL's
/// ML-KEM encapsulation does not accept external randomness, so draft test
/// vectors are verified against the pure-Dart backend instead.
///
/// Prefer [AtPqc.xWing], which auto-resolves to this backend when libcrypto
/// supports ML-KEM-768 and falls back to pure-Dart otherwise. Construct via
/// [XWingFfiAlgo.fromLib] only to pin a specific [DynamicLibrary]
/// (e.g. loaded via [tryLoadLibCrypto]).
final class XWingFfiAlgo implements AtKemAlgorithm {
  final MlKem768FfiAlgo _mlKem;
  final X25519FfiAlgo _x25519;

  XWingFfiAlgo.fromLib(DynamicLibrary lib)
      : _mlKem = MlKem768FfiAlgo.fromLib(lib),
        _x25519 = X25519FfiAlgo.fromLib(lib);

  static const int seedLength = XWingSizes.seedLength;
  static const int publicKeyLength = XWingSizes.publicKeyLength;
  static const int ciphertextLength = XWingSizes.ciphertextLength;
  static const int sharedSecretLength = XWingSizes.sharedSecretLength;

  static const int _mlKemPublicKeyLength = MlKem768Sizes.publicKeyBytes;
  static const int _mlKemCiphertextLength = MlKem768Sizes.ciphertextBytes;

  /// `XWingLabel`: the ASCII bytes of `\.//^\`.
  static final Uint8List _label =
      Uint8List.fromList([0x5c, 0x2e, 0x2f, 0x2f, 0x5e, 0x5c]);

  /// Generate an X-Wing key pair.
  ///
  /// Returns `(publicKey: 1216 bytes, secretKey: 32 bytes)` — the secret key IS
  /// the [seed]; everything else is re-derived from it on decapsulation. Pass a
  /// 32-byte [seed] for deterministic generation (testing), otherwise one is
  /// drawn from a secure random source.
  @override
  Future<({Uint8List publicKey, Uint8List secretKey})> generateKeyPair(
      [Uint8List? seed]) async {
    seed ??= _randomSeed();
    final _Expanded e = await _expand(seed);
    try {
      final Uint8List publicKey =
          _assemblePublicKey(e.mlKemKeyPair.publicKey, e.x25519Public);
      return (publicKey: publicKey, secretKey: Uint8List.fromList(seed));
    } finally {
      _mlKem.releaseKeyPair(e.mlKemKeyPair);
    }
  }

  /// `pk_M || pk_X`. The fixed offsets below (`0..1184`, `1184..1216`) assume
  /// the ML-KEM-768 component is exactly [_mlKemPublicKeyLength] bytes — same
  /// reasoning as [_combine]'s.
  Uint8List _assemblePublicKey(
      Uint8List mlKemPublicKey, Uint8List x25519Public) {
    checkOutputLength(mlKemPublicKey.length, _mlKemPublicKeyLength,
        operation: 'ML-KEM-768 generateKeyPair', label: 'public key');
    return Uint8List(publicKeyLength)
      ..setRange(0, _mlKemPublicKeyLength, mlKemPublicKey)
      ..setRange(_mlKemPublicKeyLength, publicKeyLength, x25519Public);
  }

  /// Exposes [_assemblePublicKey] to prove its ML-KEM-768 public-key length
  /// guard is wired to the correct constant — not a production entry point.
  @visibleForTesting
  Uint8List assemblePublicKeyForTesting(
          Uint8List mlKemPublicKey, Uint8List x25519Public) =>
      _assemblePublicKey(mlKemPublicKey, x25519Public);

  @override
  Future<({Uint8List ciphertext, Uint8List sharedSecret})> encapsulate(
      Uint8List publicKey) async {
    if (publicKey.length != publicKeyLength) {
      throw ArgumentError.value(publicKey.length, 'publicKey',
          'X-Wing public key must be $publicKeyLength bytes');
    }
    final Uint8List mlKemPublic = publicKey.sublist(0, _mlKemPublicKeyLength);
    final Uint8List x25519Public = publicKey.sublist(_mlKemPublicKeyLength);

    final (ciphertext: ctM, sharedSecret: ssM) =
        await _mlKem.encapsulate(mlKemPublic);

    final ephemeral = await _x25519.generateKeyPair();
    final Uint8List ctX = ephemeral.publicKey;
    final Uint8List ssX = await _x25519.dh(ephemeral.privateKey, x25519Public);

    final Uint8List ciphertext = _assembleCiphertext(ctM, ctX);
    return (
      ciphertext: ciphertext,
      sharedSecret: _combine(ssM, ssX, ctX, x25519Public),
    );
  }

  /// `ct_M || ct_X`. The fixed offsets below (`0..1088`, `1088..1120`) assume
  /// the ML-KEM-768 component is exactly [_mlKemCiphertextLength] bytes —
  /// same reasoning as [_combine]'s.
  Uint8List _assembleCiphertext(Uint8List ctM, Uint8List ctX) {
    checkOutputLength(ctM.length, _mlKemCiphertextLength,
        operation: 'ML-KEM-768 encapsulate', label: 'ciphertext');
    return Uint8List(ciphertextLength)
      ..setRange(0, _mlKemCiphertextLength, ctM)
      ..setRange(_mlKemCiphertextLength, ciphertextLength, ctX);
  }

  /// Exposes [_assembleCiphertext] to prove its ML-KEM-768 ciphertext length
  /// guard is wired to the correct constant — not a production entry point.
  @visibleForTesting
  Uint8List assembleCiphertextForTesting(Uint8List ctM, Uint8List ctX) =>
      _assembleCiphertext(ctM, ctX);

  @override
  Future<Uint8List> decapsulate(
      Uint8List secretKey, Uint8List ciphertext) async {
    if (secretKey.length != seedLength) {
      throw ArgumentError.value(secretKey.length, 'secretKey',
          'X-Wing secret key must be the $seedLength-byte seed');
    }
    if (ciphertext.length != ciphertextLength) {
      throw ArgumentError.value(ciphertext.length, 'ciphertext',
          'X-Wing ciphertext must be $ciphertextLength bytes');
    }
    final Uint8List ctM = ciphertext.sublist(0, _mlKemCiphertextLength);
    final Uint8List ctX = ciphertext.sublist(_mlKemCiphertextLength);

    final _Expanded e = await _expand(secretKey);
    try {
      final Uint8List ssM =
          await _mlKem.decapsulate(e.mlKemKeyPair.secretKey, ctM);
      final Uint8List ssX = await _x25519.dh(e.x25519Secret, ctX);
      return _combine(ssM, ssX, ctX, e.x25519Public);
    } finally {
      _mlKem.releaseKeyPair(e.mlKemKeyPair);
    }
  }

  /// `expandDecapsulationKey(sk)`: SHAKE-256(sk, 96 bytes); bytes [0:64] are
  /// ML-KEM-768's (d || z), bytes [64:96] the X25519 secret key. The ML-KEM key
  /// pair is materialised in OpenSSL via [MlKem768FfiAlgo.generateKeyPair]
  /// — callers must release it (see [generateKeyPair]/[decapsulate]).
  Future<_Expanded> _expand(Uint8List seed) async {
    if (seed.length != seedLength) {
      throw ArgumentError.value(
          seed.length, 'seed', 'X-Wing seed must be $seedLength bytes');
    }
    final SHAKEDigest shake = SHAKEDigest(256);
    shake.update(seed, 0, seed.length);
    final Uint8List expanded = Uint8List(96);
    shake.doOutput(expanded, 0, 96);

    final ({Uint8List publicKey, Uint8List secretKey}) mlKemKeyPair =
        await _mlKem.generateKeyPair(expanded.sublist(0, 64));
    final Uint8List skX = expanded.sublist(64, 96);
    final Uint8List pkX = _x25519.publicKeyFromPrivate(skX);
    return _Expanded(
      mlKemKeyPair: mlKemKeyPair,
      x25519Secret: skX,
      x25519Public: pkX,
    );
  }

  /// `SHA3-256(ss_M || ss_X || ct_X || pk_X || XWingLabel)`.
  ///
  /// Shared choke point for both [encapsulate] and [decapsulate] — the fixed
  /// offsets below (`0..32`, `32..64`) assume `ssM`/`ssX` are each exactly 32
  /// bytes; checking it here covers both call sites in one place.
  Uint8List _combine(
      Uint8List ssM, Uint8List ssX, Uint8List ctX, Uint8List pkX) {
    checkOutputLength(ssM.length, MlKem768Sizes.sharedSecretBytes,
        operation: 'X-Wing', label: 'ML-KEM-768 shared secret component');
    checkOutputLength(ssX.length, XWingSizes.x25519ComponentLength,
        operation: 'X-Wing', label: 'X25519 shared secret component');
    final Uint8List input =
        Uint8List(ssM.length + ssX.length + ctX.length + pkX.length + 6)
          ..setRange(0, 32, ssM)
          ..setRange(32, 64, ssX)
          ..setRange(64, 96, ctX)
          ..setRange(96, 128, pkX)
          ..setRange(128, 134, _label);
    return SHA3Digest(256).process(input);
  }

  /// Exposes [_combine] to prove its `ssM`/`ssX` length guards are wired to
  /// the correct constants — not a production entry point.
  @visibleForTesting
  Uint8List combineForTesting(
          Uint8List ssM, Uint8List ssX, Uint8List ctX, Uint8List pkX) =>
      _combine(ssM, ssX, ctX, pkX);

  Uint8List _randomSeed() {
    final Random random = Random.secure();
    return Uint8List.fromList(
        List<int>.generate(seedLength, (_) => random.nextInt(256)));
  }
}

class _Expanded {
  final ({Uint8List publicKey, Uint8List secretKey}) mlKemKeyPair;
  final Uint8List x25519Secret;
  final Uint8List x25519Public;

  _Expanded({
    required this.mlKemKeyPair,
    required this.x25519Secret,
    required this.x25519Public,
  });
}
