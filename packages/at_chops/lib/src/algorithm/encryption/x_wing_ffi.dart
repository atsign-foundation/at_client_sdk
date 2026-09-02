import 'dart:async';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:at_chops/src/algorithm/at_algorithm.dart';
import 'package:at_chops/src/algorithm/encryption/ml_kem_768_ffi.dart';
import 'package:at_chops/src/algorithm/encryption/x25519_ffi_algo.dart';
import 'package:at_chops/src/algorithm/encryption/x_wing_core.dart';

/// X-Wing hybrid post-quantum/traditional KEM (IANA HPKE KEM id `0x647A`)
/// backed by OpenSSL 3 via Dart FFI.
///
/// See [XWingPureDartAlgo] for which document to cite and why.
///
/// X-Wing has no native OpenSSL primitive, so this composes [MlKem768FfiAlgo]
/// (ML-KEM-768) and [X25519FfiAlgo] (X25519). The seed expansion (SHAKE-256),
/// the shared-secret combiner (SHA3-256) and the byte layouts are the
/// package-internal `XWingCore`, shared with `XWingPureDartAlgo`, so public
/// keys, ciphertexts and shared secrets are fully interoperable between the
/// FFI and pure-Dart backends. This backend is still checked against the
/// published `0x647A` vectors in its own right — the working group's JSON is
/// the independent oracle, and interop tests alone would pass with both
/// backends wrong in the same way.
///
/// Unlike `XWingPureDartAlgo`, there is no derandomized encapsulation: OpenSSL's
/// ML-KEM encapsulation does not accept external randomness, so draft test
/// vectors are verified against the pure-Dart backend instead.
///
/// Prefer [AtPqc.xWing], which auto-resolves to this backend when libcrypto
/// supports ML-KEM-768 and falls back to pure-Dart otherwise. Construct via
/// [XWingFfiAlgo.fromLib] only to pin a specific [DynamicLibrary]
/// (e.g. loaded via [tryLoadLibCrypto]).
final class XWingFfiAlgo with KemSeedMixin implements AtKemAlgorithm {
  final MlKem768FfiAlgo _mlKem;
  final X25519FfiAlgo _x25519;

  XWingFfiAlgo.fromLib(DynamicLibrary lib)
      : _mlKem = MlKem768FfiAlgo.fromLib(lib),
        _x25519 = X25519FfiAlgo.fromLib(lib);

  @override
  int get kemSeedLength => seedLength;

  @override
  String get kemSeedDescription => 'an X-Wing seed';

  static const int seedLength = XWingCore.seedLength;
  static const int publicKeyLength = XWingCore.publicKeyLength;
  static const int ciphertextLength = XWingCore.ciphertextLength;
  static const int sharedSecretLength = XWingCore.sharedSecretLength;

  /// Generate an X-Wing key pair.
  ///
  /// Returns `(publicKey: 1216 bytes, secretKey: 32 bytes)` — the secret key IS
  /// the [seed]; everything else is re-derived from it on decapsulation. Pass a
  /// 32-byte [seed] for deterministic generation (testing), otherwise one is
  /// drawn from a secure random source.
  @override
  Future<({Uint8List publicKey, Uint8List secretKey})> generateKeyPair(
      [Uint8List? seed]) async {
    seed ??= newSeed();
    final _Expanded e = await _expand(seed);
    try {
      final Uint8List publicKey =
          XWingCore.concatPublicKey(e.mlKemKeyPair.publicKey, e.x25519Public);
      return (publicKey: publicKey, secretKey: Uint8List.fromList(seed));
    } finally {
      _mlKem.releaseKeyPair(e.mlKemKeyPair);
    }
  }

  /// Unlike [MlKem768FfiAlgo], this backend's secret key is the seed itself
  /// rather than an OpenSSL handle, so a key recovered through
  /// [keyPairFromSeed] does survive a restart.
  @override
  Future<({Uint8List publicKey, Uint8List secretKey})> keyPairFromValidatedSeed(
          Uint8List seed) =>
      generateKeyPair(seed);

  @override
  Future<({Uint8List ciphertext, Uint8List sharedSecret})> encapsulate(
      Uint8List publicKey) async {
    final halves = XWingCore.splitPublicKey(publicKey);

    final (ciphertext: ctM, sharedSecret: ssM) =
        await _mlKem.encapsulate(halves.mlKem);

    final ephemeral = await _x25519.generateKeyPair();
    final Uint8List ctX = ephemeral.publicKey;
    final Uint8List ssX = await _x25519.dh(ephemeral.privateKey, halves.x25519);

    return (
      ciphertext: XWingCore.concatCiphertext(ctM, ctX),
      sharedSecret: XWingCore.combine(ssM, ssX, ctX, halves.x25519),
    );
  }

  @override
  Future<Uint8List> decapsulate(
      Uint8List secretKey, Uint8List ciphertext) async {
    XWingCore.checkDecapsulationInputs(secretKey, ciphertext);
    final ct = XWingCore.splitCiphertext(ciphertext);

    final _Expanded e = await _expand(secretKey);
    try {
      final Uint8List ssM =
          await _mlKem.decapsulate(e.mlKemKeyPair.secretKey, ct.mlKem);
      final Uint8List ssX = await _x25519.dh(e.x25519Secret, ct.x25519);
      return XWingCore.combine(ssM, ssX, ct.x25519, e.x25519Public);
    } finally {
      _mlKem.releaseKeyPair(e.mlKemKeyPair);
    }
  }

  /// Materialises [XWingCore.expandSeed]'s halves with this backend's
  /// components. The ML-KEM key pair is materialised in OpenSSL via
  /// [MlKem768FfiAlgo.generateKeyPair] — callers must release it (see
  /// [generateKeyPair]/[decapsulate]).
  Future<_Expanded> _expand(Uint8List seed) async {
    final halves = XWingCore.expandSeed(seed);
    final ({Uint8List publicKey, Uint8List secretKey}) mlKemKeyPair =
        await _mlKem.generateKeyPair(halves.mlKemSeed);
    final Uint8List skX = halves.x25519Secret;
    final Uint8List pkX = _x25519.publicKeyFromPrivate(skX);
    return _Expanded(
      mlKemKeyPair: mlKemKeyPair,
      x25519Secret: skX,
      x25519Public: pkX,
    );
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
