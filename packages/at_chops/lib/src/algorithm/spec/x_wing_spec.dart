import 'dart:math' show Random;
import 'dart:typed_data';

import 'package:at_chops/src/algorithm/spec/ml_kem_768_spec.dart';
import 'package:at_chops/src/algorithm/spec/output_length.dart';
import 'package:pointycastle/digests/sha3.dart';

/// X-Wing hybrid KEM (draft-connolly-cfrg-xwing-kem-10) fixed byte sizes,
/// byte-assembly, and shared-secret combiner logic — shared by `XWingFfiAlgo`
/// and `XWingPureDartAlgo` so both enforce identical lengths and layouts;
/// only the ML-KEM-768/X25519 backend they compose differs between them.
abstract final class XWingSizes {
  /// Secret (decapsulation) key size — the 32-byte seed everything else is
  /// expanded from.
  static const int seedLength = 32;

  /// Public (encapsulation) key size: `pk_M || pk_X` (1184 + 32).
  static const int publicKeyLength = 1216;

  /// Ciphertext size: `ct_M || ct_X` (1088 + 32).
  static const int ciphertextLength = 1120;

  /// Shared secret size.
  static const int sharedSecretLength = 32;

  /// X25519 sub-component size — `pk_X`, `ct_X` and `ss_X` are each this long.
  /// Distinct from [sharedSecretLength], which is the SHA3-256 combiner's
  /// output; these two are equal by coincidence, not by construction.
  static const int x25519ComponentLength = 32;

  /// `XWingLabel`: the ASCII bytes of `\.//^\`.
  static final Uint8List _label =
      Uint8List.fromList([0x5c, 0x2e, 0x2f, 0x2f, 0x5e, 0x5c]);

  /// `pk_M || pk_X`. The fixed offsets below (`0..1184`, `1184..1216`) assume
  /// the ML-KEM-768 component is exactly [MlKem768Sizes.publicKeyBytes] bytes
  /// — same reasoning as [combineSharedSecret]'s.
  static Uint8List assemblePublicKey(
      Uint8List mlKemPublicKey, Uint8List x25519Public) {
    checkOutputLength(mlKemPublicKey.length, MlKem768Sizes.publicKeyBytes,
        operation: 'ML-KEM-768 generateKeyPair', label: 'public key');
    return Uint8List(publicKeyLength)
      ..setRange(0, MlKem768Sizes.publicKeyBytes, mlKemPublicKey)
      ..setRange(MlKem768Sizes.publicKeyBytes, publicKeyLength, x25519Public);
  }

  /// `ct_M || ct_X`. The fixed offsets below (`0..1088`, `1088..1120`) assume
  /// the ML-KEM-768 component is exactly [MlKem768Sizes.ciphertextBytes]
  /// bytes — same reasoning as [combineSharedSecret]'s.
  static Uint8List assembleCiphertext(Uint8List ctM, Uint8List ctX) {
    checkOutputLength(ctM.length, MlKem768Sizes.ciphertextBytes,
        operation: 'ML-KEM-768 encapsulate', label: 'ciphertext');
    return Uint8List(ciphertextLength)
      ..setRange(0, MlKem768Sizes.ciphertextBytes, ctM)
      ..setRange(MlKem768Sizes.ciphertextBytes, ciphertextLength, ctX);
  }

  /// `SHA3-256(ss_M || ss_X || ct_X || pk_X || XWingLabel)`.
  ///
  /// Shared choke point for both encapsulation and decapsulation — the fixed
  /// offsets below (`0..32`, `32..64`) assume `ssM`/`ssX` are each exactly 32
  /// bytes; checking it here covers both call sites in one place.
  static Uint8List combineSharedSecret(
      Uint8List ssM, Uint8List ssX, Uint8List ctX, Uint8List pkX) {
    checkOutputLength(ssM.length, MlKem768Sizes.sharedSecretBytes,
        operation: 'X-Wing', label: 'ML-KEM-768 shared secret component');
    checkOutputLength(ssX.length, x25519ComponentLength,
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

  static Uint8List randomSeed() {
    final Random random = Random.secure();
    return Uint8List.fromList(
        List<int>.generate(seedLength, (_) => random.nextInt(256)));
  }
}
