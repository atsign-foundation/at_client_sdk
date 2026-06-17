import 'dart:async';
import 'dart:ffi';
import 'dart:math' show Random;
import 'dart:typed_data';

import 'package:at_chops/src/algorithm/at_algorithm.dart';
import 'package:at_chops/src/algorithm/encryption/ml_kem_768_ffi_algo.dart';
import 'package:at_chops/src/algorithm/encryption/x25519_ffi_algo.dart';
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
/// The caller loads libcrypto (e.g. via [tryLoadLibCrypto]) and passes the
/// resulting [DynamicLibrary] in. at_chops does no auto-resolution.
final class XWingFfiAlgo implements AtKemAlgorithm {
  final MlKem768FfiAlgo _mlKem;
  final X25519FfiAlgo _x25519;

  XWingFfiAlgo.fromLib(DynamicLibrary lib)
      : _mlKem = MlKem768FfiAlgo.fromLib(lib),
        _x25519 = X25519FfiAlgo.fromLib(lib);

  static const int seedLength = 32;
  static const int publicKeyLength = 1216;
  static const int ciphertextLength = 1120;
  static const int sharedSecretLength = 32;

  static const int _mlKemPublicKeyLength = 1184;
  static const int _mlKemCiphertextLength = 1088;

  /// `XWingLabel`: the ASCII bytes of `\.//^\`.
  static final Uint8List _label =
      Uint8List.fromList([0x5c, 0x2e, 0x2f, 0x2f, 0x5e, 0x5c]);

  /// Generate an X-Wing key pair.
  ///
  /// Returns `(publicKey: 1216 bytes, secretKey: 32 bytes)` — the secret key IS
  /// the [seed]; everything else is re-derived from it on decapsulation. Pass a
  /// 32-byte [seed] for deterministic generation (testing), otherwise one is
  /// drawn from a secure random source.
  Future<({Uint8List publicKey, Uint8List secretKey})> generateKeyPair(
      [Uint8List? seed]) async {
    seed ??= _randomSeed();
    final _Expanded e = await _expand(seed);
    try {
      final Uint8List publicKey = Uint8List(publicKeyLength)
        ..setRange(0, _mlKemPublicKeyLength, e.mlKemKeyPair.publicKey)
        ..setRange(_mlKemPublicKeyLength, publicKeyLength, e.x25519Public);
      return (publicKey: publicKey, secretKey: Uint8List.fromList(seed));
    } finally {
      _mlKem.releaseKeyPair(e.mlKemKeyPair);
    }
  }

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

    final Uint8List ciphertext = Uint8List(ciphertextLength)
      ..setRange(0, _mlKemCiphertextLength, ctM)
      ..setRange(_mlKemCiphertextLength, ciphertextLength, ctX);
    return (
      ciphertext: ciphertext,
      sharedSecret: _combine(ssM, ssX, ctX, x25519Public),
    );
  }

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
  /// pair is materialised in OpenSSL via [MlKem768FfiAlgo.generateKeyPairFromSeed]
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
        await _mlKem.generateKeyPairFromSeed(expanded.sublist(0, 64));
    final Uint8List skX = expanded.sublist(64, 96);
    final Uint8List pkX = _x25519.publicKeyFromPrivate(skX);
    return _Expanded(
      mlKemKeyPair: mlKemKeyPair,
      x25519Secret: skX,
      x25519Public: pkX,
    );
  }

  /// `SHA3-256(ss_M || ss_X || ct_X || pk_X || XWingLabel)`.
  Uint8List _combine(
      Uint8List ssM, Uint8List ssX, Uint8List ctX, Uint8List pkX) {
    final Uint8List input =
        Uint8List(ssM.length + ssX.length + ctX.length + pkX.length + 6)
          ..setRange(0, 32, ssM)
          ..setRange(32, 64, ssX)
          ..setRange(64, 96, ctX)
          ..setRange(96, 128, pkX)
          ..setRange(128, 134, _label);
    return SHA3Digest(256).process(input);
  }

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
