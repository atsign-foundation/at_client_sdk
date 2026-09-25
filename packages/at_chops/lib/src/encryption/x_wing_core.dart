import 'dart:typed_data';

import 'package:pointycastle/digests/sha3.dart';
import 'package:pointycastle/digests/shake.dart';

/// The X-Wing construction's pure computation, shared by the pure-Dart and
/// FFI backends: byte layouts and their validations, the SHAKE-256 seed
/// expansion, and the SHA3-256 shared-secret combiner.
///
/// Package-internal. The backends compose different component implementations
/// (pqcrypto + `package:cryptography` vs OpenSSL) around these bytes, and
/// each is checked against the IETF HPKE working group's published `0x647A`
/// vectors in its own right — the published JSON is the independent oracle
/// that catches a defect here, which backend interop tests alone would not.
///
/// Deliberately free of `dart:ffi`: the pure-Dart backend is exported by the
/// main (web-safe) barrel, so this file must stay out of the ffi import
/// graph.
final class XWingCore {
  XWingCore._();

  static const int seedLength = 32;
  static const int publicKeyLength = 1216;
  static const int ciphertextLength = 1120;
  static const int sharedSecretLength = 32;

  static const int mlKemPublicKeyLength = 1184;
  static const int mlKemCiphertextLength = 1088;

  /// `XWingLabel`: the ASCII bytes of `\.//^\`.
  static final Uint8List label =
      Uint8List.fromList([0x5c, 0x2e, 0x2f, 0x2f, 0x5e, 0x5c]);

  /// `expandDecapsulationKey(sk)`: SHAKE-256(seed, 96 bytes); bytes [0:64]
  /// are ML-KEM-768's `d || z`, bytes [64:96] the X25519 secret key.
  static ({Uint8List mlKemSeed, Uint8List x25519Secret}) expandSeed(
      Uint8List seed) {
    if (seed.length != seedLength) {
      throw ArgumentError.value(
          seed.length, 'seed', 'X-Wing seed must be $seedLength bytes');
    }
    final SHAKEDigest shake = SHAKEDigest(256);
    shake.update(seed, 0, seed.length);
    final Uint8List expanded = Uint8List(96);
    shake.doOutput(expanded, 0, 96);
    return (
      mlKemSeed: expanded.sublist(0, 64),
      x25519Secret: expanded.sublist(64, 96),
    );
  }

  /// `SHA3-256(ss_M || ss_X || ct_X || pk_X || XWingLabel)`.
  static Uint8List combine(
      Uint8List ssM, Uint8List ssX, Uint8List ctX, Uint8List pkX) {
    final Uint8List input =
        Uint8List(ssM.length + ssX.length + ctX.length + pkX.length + 6)
          ..setRange(0, 32, ssM)
          ..setRange(32, 64, ssX)
          ..setRange(64, 96, ctX)
          ..setRange(96, 128, pkX)
          ..setRange(128, 134, label);
    return SHA3Digest(256).process(input);
  }

  /// `pk_M || pk_X` (1184 + 32 = 1216 bytes).
  static Uint8List concatPublicKey(Uint8List pkM, Uint8List pkX) =>
      Uint8List(publicKeyLength)
        ..setRange(0, mlKemPublicKeyLength, pkM)
        ..setRange(mlKemPublicKeyLength, publicKeyLength, pkX);

  /// Splits a validated X-Wing public key into its component halves.
  static ({Uint8List mlKem, Uint8List x25519}) splitPublicKey(
      Uint8List publicKey) {
    if (publicKey.length != publicKeyLength) {
      throw ArgumentError.value(publicKey.length, 'publicKey',
          'X-Wing public key must be $publicKeyLength bytes');
    }
    return (
      mlKem: publicKey.sublist(0, mlKemPublicKeyLength),
      x25519: publicKey.sublist(mlKemPublicKeyLength),
    );
  }

  /// `ct_M || ct_X` (1088 + 32 = 1120 bytes).
  static Uint8List concatCiphertext(Uint8List ctM, Uint8List ctX) =>
      Uint8List(ciphertextLength)
        ..setRange(0, mlKemCiphertextLength, ctM)
        ..setRange(mlKemCiphertextLength, ciphertextLength, ctX);

  /// Splits an X-Wing ciphertext into its component halves. Callers validate
  /// the length first (see [checkDecapsulationInputs]).
  static ({Uint8List mlKem, Uint8List x25519}) splitCiphertext(
          Uint8List ciphertext) =>
      (
        mlKem: ciphertext.sublist(0, mlKemCiphertextLength),
        x25519: ciphertext.sublist(mlKemCiphertextLength),
      );

  /// Rejects wrong-length decapsulation inputs; both backends take the
  /// 32-byte seed as their secret key.
  static void checkDecapsulationInputs(
      Uint8List secretKey, Uint8List ciphertext) {
    if (secretKey.length != seedLength) {
      throw ArgumentError.value(secretKey.length, 'secretKey',
          'X-Wing secret key must be the $seedLength-byte seed');
    }
    if (ciphertext.length != ciphertextLength) {
      throw ArgumentError.value(ciphertext.length, 'ciphertext',
          'X-Wing ciphertext must be $ciphertextLength bytes');
    }
  }
}
